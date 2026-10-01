# Vehicle-to-grid discharge reshapes electric vehicle charging behavior

Replication code for the manuscript:

> **Vehicle-to-grid discharge reshapes electric vehicle charging behavior**  
>
> **Authors:** Bo Wang, Qianhui Liu, Zhaohua Wang, Pengfei Liu, Zhaosheng Zhang, Peng Liu, Haixu Yang, Nana Deng, Heqi Wang, and Xiaoli Han  
>
> **Corresponding authors:** Zhaohua Wang, Pengfei Liu, and Zhaosheng Zhang

This repository contains the Stata code used for the main analyses and
Supplementary Information (SI) robustness analyses.

## Repository contents

```text
V2G-charging-behavior/
├── README.md
├── main_do.do
├── SI.do
├── .gitignore
├── data/
│   ├── README.md
│   └── private/
│       └── .gitkeep
├── source_data/
│   └── README.md
└── results/
    ├── main/
    │   └── .gitkeep
    └── SI/
        └── .gitkeep
```

- `main_do.do` reproduces the main DID, event-study, and heterogeneity analyses.
- `SI.do` runs the supplementary robustness analyses, including alternative
  event-study reference periods and fixed-effect specifications.
- `data/README.md` documents the restricted analysis-data requirements.
- `data/private/` is reserved for authorized restricted analysis data and is
  excluded from Git tracking.
- `source_data/` is reserved for aggregated and derived source data that may be
  distributed with the Supplementary Information, subject to the applicable
  data-use agreement.
- `results/` receives generated logs, tables, and machine-readable result files.

## System requirements

The analysis is written for **Stata 16.0**.

The scripts use the user-written packages:

- `ftools`
- `reghdfe`

If these packages are not available, the scripts attempt to install them from SSC.

## Data availability

The vehicle-level operational and charging records used in this study are subject
to data-access, privacy and data-use restrictions and cannot be publicly
redistributed by the authors. Researchers seeking access to comparable anonymized
vehicle-operation data may apply to the NDANEV Open Laboratory through the data
provider’s standard application, review and authorization procedures. To support
reproducibility of the reported results, aggregated and derived source data
underlying the figures and tables are provided with the Supplementary Information,
subject to the applicable data-use agreement.

### Reproducing the analysis with authorized data

The restricted vehicle-level analysis dataset is therefore **not included in this
public repository**. Researchers with authorized access to the required analysis
data should save the Stata dataset as:

```text
data/private/analysis_data.dta
```

The repository's `.gitignore` rules prevent files in `data/private/` from being
committed to GitHub.

See `data/README.md` for the variables expected by the current analysis scripts.

## Instructions for use

1. Download or clone this repository.
2. If you have authorized access to the required restricted analysis data, save
   the analysis dataset as:

```text
data/private/analysis_data.dta
```

3. Open Stata and set the working directory to the **root of this repository**.

For example:

```stata
cd "D:/path/to/V2G-charging-behavior"
```

4. Run the main analysis:

```stata
do "main_do.do"
```

Main-analysis outputs will be written to:

```text
results/main/
```

5. Run the Supplementary Information robustness analysis:

```stata
do "SI.do"
```

SI outputs will be written to:

```text
results/SI/
```

## Main analysis

`main_do.do` implements the manuscript's principal specifications, including:

- static DID specifications across the analysis windows;
- event-study estimates;
- vehicle-type heterogeneity;
- holiday heterogeneity;
- discharge-count heterogeneity; and
- anticipation-related analyses.

The benchmark specification uses vehicle fixed effects and
province-by-calendar-week fixed effects, with standard errors clustered at the
vehicle level. The script contains detailed comments documenting the exact
specification used for each analysis.

## Supplementary Information

`SI.do` contains robustness analyses for:

- alternative event-study omitted reference periods; and
- alternative fixed-effect specifications.

The SI script retains the same outcome construction, clustering approach, and
core controls as documented in the code, except where a robustness specification
explicitly changes the fixed effects or reference period.

## Source data for figures and tables

Aggregated and derived source data underlying the figures and tables are provided
with the Supplementary Information, subject to the applicable data-use agreement.

The `source_data/` directory in this repository is reserved for those shareable
files if their distribution through GitHub is permitted. If the source data are
distributed only through the journal's Supplementary Information, the directory
may remain empty and a link to the published Supplementary Information can be
added after publication.

Restricted vehicle-level records must not be committed to `source_data/`.

## Output files

The Stata scripts automatically create/export analysis logs and result files.
Generated outputs under `results/` are ignored by Git by default. This keeps the
public repository code-focused and reduces the risk of accidentally publishing
derived information that has not undergone disclosure review.

Any aggregate tables, figures, or derived source-data files intended for public
release should be added deliberately only after confirming that distribution is
permitted under the applicable data-use agreement.


## Authors and affiliations

**Bo Wang**<sup>a,f,g</sup>, **Qianhui Liu**<sup>a,f,g</sup>, **Zhaohua Wang**<sup>b,f,g,*</sup>, **Pengfei Liu**<sup>c,d,*</sup>, **Peng Liu**<sup>d</sup>, **Zhaosheng Zhang**<sup>e,*</sup>, **Peng Liu**<sup>e</sup>, **Haixu Yang**<sup>e</sup>, **Nana Deng**<sup>b,f,g</sup>, **Heqi Wang**<sup>a,f,g</sup>, and **Xiaoli Han**<sup>a,f,g</sup>

<sup>a</sup> School of Management, Beijing Institute of Technology, Beijing 100081, China  
<sup>b</sup> School of Economics, Beijing Institute of Technology, Beijing 100081, China  
<sup>c</sup> Department of Environmental and Natural Resource Economics, University of Rhode Island, USA  
<sup>d</sup> MoE Key Laboratory of Complex System Analysis and Management Decision, School of Economics and Management, Beihang University, Beijing 100191, China  
<sup>e</sup> National Engineering Research Center of Electric Vehicles, Beijing Institute of Technology, Beijing 100081, China  
<sup>f</sup> Digital Economy and Policy Intelligentization Key Laboratory of Ministry of Industry and Information Technology, Beijing 100081, China  
<sup>g</sup> Research Center for Sustainable Development & Intelligent Decision, Beijing Institute of Technology, Beijing 100081, China

<sup>*</sup> **Corresponding authors**

- Zhaohua Wang — wangzhaohua@bit.edu.cn
- Pengfei Liu — pengfei_liu@uri.edu
- Zhaosheng Zhang — zhangzhaosheng@bit.edu.cn
