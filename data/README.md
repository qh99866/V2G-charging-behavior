# Restricted Analysis Data

## Data availability

The vehicle-level operational and charging records used in this study are subject
to data-access, privacy and data-use restrictions and cannot be publicly
redistributed by the authors. Researchers seeking access to comparable anonymized
vehicle-operation data may apply to the NDANEV Open Laboratory through the data
provider’s standard application, review and authorization procedures. To support
reproducibility of the reported results, aggregated and derived source data
underlying the figures and tables are provided with the Supplementary Information,
subject to the applicable data-use agreement.

## Local setup for authorized users

The restricted vehicle-level dataset is not included in this GitHub repository.

Researchers with authorized access to the analysis data should place the Stata
dataset at:

```text
data/private/analysis_data.dta
```

Files inside `data/private/` are excluded from Git tracking by the repository's
`.gitignore` rules.

## Expected analysis variables

The current Stata scripts expect the authorized analysis dataset to contain the
following variables:

| Variable | Role in the analysis |
|---|---|
| `vid` | Vehicle identifier (source/string ID) |
| `vehicle_id` | Numeric vehicle identifier |
| `event_id` | Discharge-event identifier |
| `y1_chg_start_soc` | Charging-start state of charge |
| `y2_chg_end_soc` | Charging-end state of charge |
| `y3_chg_energy` | Charging energy |
| `y4_chg_duration_h` | Charging duration (hours) |
| `rel_k` | Relative charging-event index around discharge |
| `post` | Post-discharge indicator |
| `complete20_calc` | Indicator used for analysis-window construction |
| `vehicle_discharge_count_desc` | Vehicle-level discharge-count measure |
| `discharge_start_time` | Discharge start time |
| `charge_start_time` | Charge start time |
| `holiday` | Holiday indicator/category source |
| `car_type` | Vehicle type |
| `province` | Province |

The working dataset inspected during repository preparation also contained
`area_id`, `y5_adjacent_gap_h`, `multi_discharge_vehicle_desc`, `week`, `mon`,
and `energy_total_capacity`. These variables are not listed above as required
inputs for the current main/SI scripts unless referenced by a later code revision.

## Public source data

Aggregated and derived source data underlying figures and tables are handled
separately from the restricted vehicle-level records. See:

```text
source_data/README.md
```

for the repository's source-data convention.

## Confidentiality

Do not commit restricted `.dta` files, row-level derived datasets, direct or
indirect identifiers, or other confidential records to the public repository.
