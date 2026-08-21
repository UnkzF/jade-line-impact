# Impactos do Metrô de São Paulo no Padrão de Viagens: Estudo de Caso na Linha 13 - Jade

This repository contains the analytical pipeline and codebase for a Master's dissertation evaluating the causal transportation impacts of the São Paulo Metro Line 13 - Jade.

The study leverages decades of Origin-Destination (OD) survey data (1997, 2007, 2017, and 2023) to assess shifts in urban mobility patterns, analyzing both the **extensive margin** (probability of making a trip) and the **intensive margin** (total volume of trips) for residents within the transit catchment area.

## 📊 Methodology

To address endogeneity and establish causality in transit infrastructure evaluation, this pipeline implements a rigorous quasi-experimental design:

-   **Spatial Harmonization:** Custom areal interpolation (`R/spatial_helpers.R`) to harmonize distinct zoning geometries from historical OD surveys into a consistent spatial panel.
-   **Data-Driven Stratification:** Application of the CART (Classification and Regression Trees) algorithm to dynamically identify optimal income thresholds, preserving statistical power and reflecting the sociodemographic reality of the study area.
-   **Covariate Matching:** Mahalanobis distance matching to construct valid counterfactual control groups based on historical baseline covariates.
-   **Causal Inference:** Difference-in-Differences (DiD) and Triple Difference (DDD) models to estimate the Average Treatment Effect on the Treated (ATT).

## 🗂️ Repository Architecture

The workflow is completely modular and orchestrated via Quarto (`.qmd`) documents.

```         
├── analysis/
│   ├── 01_setup.qmd           # Data ingestion, spatial harmonization, and CART stratification
│   ├── 02_matching_did.qmd    # Mahalanobis matching, DiD, and DDD regression models
│   └── 03_diagnostics.qmd     # PCA overlap, Love plots, and parallel trend visualizations
├── R/
│   └── spatial_helpers.R      # Custom sf-based functions for dynamic geometry weighting
├── data/                      # Local data storage (Ignored by Git)
│   ├── raw/                   # Raw historical OD shapefiles and DBF tables
│   └── processed/             # Cleaned panel datasets and model outputs (.rds)
├── outputs/                   # High-resolution exports (SVG/PNG) and tabular results
├── renv/                      # R environment dependency tracking
├── renv.lock                  # Exact package versions for reproducibility
└── README.md
```

*Note: Due to file size constraints and data sharing protocols, the raw OD survey microdata and geospatial shapefiles in the data/ directory are not tracked in this repository.*

## ⚙️ Reproducibility

This project utilizes renv to guarantee 100% computational reproducibility. To replicate the environment on your local machine:

1.  Clone this repository.

2.  Open the .Rproj file in RStudio.

3.  Run the following command in the R console to install the exact package versions used in this research:

    ```{r}
    renv::restore()
    ```

## 📜 License

This project is licensed under the **GNU General Public License v3.0 (GPL-3.0)**.

You are free to use, modify, and distribute this analytical framework for your own spatial data science and transportation planning projects. However, any modified versions or derivative works that are distributed must also be made open-source under the same GPL-3.0 license. See the `LICENSE` file for details.
