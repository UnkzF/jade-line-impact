# R/spatial_helpers.R

library(sf)
library(dplyr)
library(purrr)

#' Generate Areal Weights between two zones
#'
#' @description
#' Calculates the proportion of the 'Source' zone that falls into the 'Target' zone.
#'
#' @note
#' Although arguments are named 'newer' and 'older', this function works for any direction.
#' - To Backcast (2023 -> 2007): zones_newer = 2023 (Source), zones_older = 2007 (Target)
#' - To Forecast (1997 -> 2007): zones_newer = 1997 (Source), zones_older = 2007 (Target)
#'
#' @param zones_newer The SOURCE layer (Denominator of weight calculation)
#' @param zones_older The TARGET layer (Geometry we are fitting into)
generate_weights <- function(zones_newer, zones_older, id_newer, id_older, year_newer, year_older) {
  
  # 1. Dynamic column names for the final output (e.g., "Z_2023")
  col_new <- paste0("Z_", year_newer)
  col_old <- paste0("Z_", year_older)
  
  # 2. Force unique temporary names before intersection
  # We use standard R renaming to be safe
  names(zones_newer)[names(zones_newer) == id_newer] <- "temp_id_new"
  names(zones_older)[names(zones_older) == id_older] <- "temp_id_old"
  
  # 3. Standardize Geometries
  zones_newer <- sf::st_make_valid(zones_newer)
  zones_older <- sf::st_make_valid(zones_older)
  
  if (sf::st_crs(zones_newer) != sf::st_crs(zones_older)) {
    zones_older <- sf::st_transform(zones_older, sf::st_crs(zones_newer))
  }
  
  # 4. Calculate areas and intersect
  zones_newer$total_area_new <- as.numeric(sf::st_area(zones_newer))
  
  intersection <- sf::st_intersection(
    zones_newer[, c("temp_id_new", "total_area_new")],
    zones_older[, c("temp_id_old")]
  )
  
  # 5. Calculate weights and rename to final year-based names
  intersection %>%
    dplyr::mutate(
      sliver_area = as.numeric(sf::st_area(.)),
      weight = sliver_area / total_area_new
    ) %>%
    sf::st_drop_geometry() %>%
    dplyr::select(temp_id_new, temp_id_old, weight) %>%
    # Rename using base R to handle dynamic string names easily
    dplyr::rename(!!col_new := temp_id_new, !!col_old := temp_id_old) %>%
    dplyr::filter(weight > 0.001)
}

#' Chain a list of correspondence tables
chain_zones <- function(table_list) {
  
  if (length(table_list) < 1) stop("Need at least one table.")
  
  purrr::reduce(table_list, function(prev, next_tab) {
    # Find the common column (e.g., "Z_2017" exists in both)
    link_col <- intersect(names(prev), names(next_tab))
    link_col <- setdiff(link_col, "weight")
    
    if (length(link_col) == 0) stop("Broken chain: No common column found between tables.")
    
    # Join and multiply weights
    dplyr::left_join(prev, next_tab, by = link_col) %>%
      dplyr::mutate(weight = weight.x * weight.y) %>%
      dplyr::select(-weight.x, -weight.y)
  }) %>%
    # Final aggregation: group by the very first and very last columns
    dplyr::group_by(across(c(1, ncol(.)-1))) %>% # Assumes weight is last column
    dplyr::summarise(weight = sum(weight), .groups = "drop")
}

#' Build a master key between any two arbitrary years
get_chain <- function(start_year, end_year, table_list, ordered_years = c(2023, 2017, 2007, 1997, 1987, 1977)) {
  
  # 1. Find where these years sit in the ordered timeline
  idx_start <- match(start_year, ordered_years)
  idx_end <- match(end_year, ordered_years)
  
  # 2. Validation
  if (is.na(idx_start)) stop(paste("Start year", start_year, "not found in ordered timeline."))
  if (is.na(idx_end)) stop(paste("End year", end_year, "not found in ordered timeline."))
  if (idx_start >= idx_end) stop("Start year must be more recent than end year.")
  
  # 3. Identify which tables bridge this gap
  # If ordered_years is [23, 17, 07...], then:
  # Table 1 is 23->17
  # Table 2 is 17->07
  # So if we want 17->87 (indices 2 to 5), we need tables 2, 3, and 4.
  needed_indices <- idx_start:(idx_end - 1)
  
  subset_list <- table_list[needed_indices]
  
  message(paste("🔗 Chaining", length(subset_list), "tables from", start_year, "to", end_year, "..."))
  
  # 4. Pass the subset to the main worker function
  return(chain_zones(subset_list))
}

#' Harmonize OD data (microdata or aggregated) to a target year
harmonize_od_data <- function(od_data, master_key, origin_col, dest_col,
                              trips_col = NULL,   # OPTIONAL: If NULL, assumes 1 trip per row
                              group_vars = NULL,  # OPTIONAL: Extra columns to keep (e.g., "Reason")
                              key_zone_newer, key_zone_older, key_weight = "weight") {
  
  # 1. Prepare Trip Counts
  # If no trips_col provided, assume each row is 1 trip
  if (is.null(trips_col)) {
    od_data$temp_trips_internal <- 1
    trips_col_name <- "temp_trips_internal"
  } else {
    trips_col_name <- trips_col
  }
  
  # 2. Standardize Key Names for easy joins
  key_std <- master_key %>%
    dplyr::rename(
      Z_New = !!key_zone_newer,
      Z_Old = !!key_zone_older,
      W = !!key_weight
    )
  
  # 3. The Harmonization Pipeline
  od_harmonized <- od_data %>%
    # JOIN 1: Translate Origins
    # We use .data[[string]] to refer to dynamic column names
    dplyr::inner_join(key_std, by = setNames("Z_New", origin_col), relationship = "many-to-many") %>%
    dplyr::rename(Orig_Old = Z_Old, W_Orig = W) %>%
    
    # JOIN 2: Translate Destinations
    dplyr::inner_join(key_std, by = setNames("Z_New", dest_col), relationship = "many-to-many") %>%
    dplyr::rename(Dest_Old = Z_Old, W_Dest = W) %>%
    
    # CALCULATE: Apply compound weights to the trip count
    dplyr::mutate(Trips_Harmonized = .data[[trips_col_name]] * W_Orig * W_Dest) %>%
    
    # AGGREGATE: Sum trips by Old OD Pair AND any extra grouping variables
    dplyr::group_by(dplyr::across(dplyr::all_of(c("Orig_Old", "Dest_Old", group_vars)))) %>%
    dplyr::summarise(Trips = sum(Trips_Harmonized), .groups = "drop")
  
  return(od_harmonized)
}