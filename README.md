# Patient Language Preference and Deep Sedation During Invasive Mechanical Ventilation

**CLIF Version:** 2.1

Measure whether patients with a Spanish-language preference documented in the EHR spend more time in deep sedation during the first 48 hours of invasive mechanical ventilation (IMV) than patients with an English-language preference, and whether secondary outcomes (ventilator-free days, time on IMV, tracheostomy, mortality) differ. This repository also contains the site script for the companion measurements project.

**1st Author:** Alex Ortiz \| **Senior Author:** Gary Weissman

## Objective

Guidelines recommend light sedation for most patients receiving IMV. Assessing a patient's mental status and titrating sedation both depend on communication between clinicians, patients, and families. This study measures the association between documented language preference and the share of early IMV hours spent in deep sedation (RASS ≤ −3), within ICUs, across a federated network of health systems.

## Important: ED + Floor Data Required

> **The cohort is adults receiving IMV in the ICU, but where IMV started and how long patients spent outside the ICU are part of the cohort definition.** Data from the **Emergency Department (ED)**, **procedural areas**, and **wards** are therefore needed in addition to ICU data.

ADT records must include `location_category` values for `ed`, `icu`, `procedural`, and floor locations, and `location_type` values for ICU subtypes (e.g., `medical_icu`, `neuro_icu`, `cardiothoracic_icu`).

## Important: RASS Documentation Required

> **The primary outcome is built from charted RASS.** Sites must map RASS to `patient_assessments` with `assessment_category = "rass"`. Episodes with no RASS documented within 8 hours of IMV start are excluded. The code reports how often and how early each site documents RASS, by language group.

## Required CLIF Tables and Fields

### 1. `patient`

| Column               | Description                        |
|----------------------|------------------------------------|
| `patient_id`         | Unique patient identifier          |
| `race_category`      | Race category                      |
| `ethnicity_category` | Ethnicity category                 |
| `sex_category`       | Sex category                       |
| `language_name`      | Language name                      |
| `language_category`  | Language category                  |
| `death_dttm`         | Date/time of death (if applicable) |

### 2. `hospitalization`

| Column                    | Description                                         |
|---------------------------|-----------------------------------------------------|
| `patient_id`              | Unique patient identifier                           |
| `hospitalization_id`      | Unique hospitalization identifier                   |
| `admission_dttm`          | Admission date/time                                 |
| `discharge_dttm`          | Discharge date/time                                 |
| `age_at_admission`        | Age at admission (years)                            |
| `discharge_category`      | Discharge disposition (incl. `hospice`, `expired`)  |
| `admission_type_category` | Admission type (e.g., ED, OSH)                      |
| `zipcode_five_digit`      | Residential ZIP code, linked to the social vulnerability score |

### 3. `adt`

| Column               | Description                                          |
|----------------------|------------------------------------------------------|
| `hospitalization_id` | Unique hospitalization identifier                    |
| `hospital_id`        | Hospital identifier                                  |
| `hospital_type`      | Hospital type (e.g., academic, community)            |
| `location_category`  | Location category (`ed`, `icu`, `procedural`, floor) |
| `location_type`      | Location subtype (e.g., `medical_icu`, `neuro_icu`)  |
| `in_dttm`            | Location entry date/time                             |
| `out_dttm`           | Location exit date/time                              |

### 4. `hospital_diagnosis`

| Column                  | Description                                      |
|-------------------------|--------------------------------------------------|
| `hospitalization_id`    | Unique hospitalization identifier                |
| `diagnosis_code`        | ICD diagnosis code                               |
| `diagnosis_code_format` | Code format (e.g., ICD10CM)                      |
| `poa_present`           | Present-on-admission flag                        |

Used for the Elixhauser comorbidity score (present-on-admission codes), COVID-19 diagnosis (ICD-10 U07.1), and cardiac-surgery complication codes.

### 5. `labs`

| Column               | Description                       |
|----------------------|-----------------------------------|
| `hospitalization_id` | Unique hospitalization identifier |
| `lab_result_dttm`    | Lab result date/time              |
| `lab_collect_dttm`   | Lab collection date/time          |
| `lab_category`       | Lab category                      |
| `lab_value_numeric`  | Numeric lab value                 |

Used for the Laboratory-based Acute Physiology Score, version 2 (LAPS2).

**Required `lab_category` values:** `albumin`, `anion_gap`, `bicarbonate`, `bilirubin_total`, `bun`, `chloride`, `creatinine`, `glucose_serum`, `hematocrit`, `hemoglobin`, `lactate`, `pco2_arterial`, `pco2_venous`, `ph_arterial`, `ph_venous`, `platelet_count`, `po2_arterial`, `so2_arterial`, `sodium`, `troponin_i`, `troponin_t`, `wbc` 

### 6. `vitals`

| Column               | Description                       |
|----------------------|-----------------------------------|
| `hospitalization_id` | Unique hospitalization identifier |
| `recorded_dttm`      | Vital sign recorded date/time     |
| `vital_category`     | Vital sign category               |
| `vital_value`        | Vital sign value                  |

Used for LAPS2 and BMI.

**Required `vital_category` values:** `dbp`, `heart_rate`, `height_cm`, `map`, `respiratory_rate`, `sbp`, `spo2`, `temp_c`, `weight_kg`

### 7. `medication_admin_continuous`

| Column               | Description                       |
|----------------------|-----------------------------------|
| `hospitalization_id` | Unique hospitalization identifier |
| `admin_dttm`         | Administration date/time          |
| `med_category`       | Medication category               |
| `med_group`          | Medication group                  |
| `med_dose`           | Dose amount                       |
| `med_dose_unit`      | Dose unit                         |

Used for continuous sedative and opioid exposure (propofol, dexmedetomidine, benzodiazepines, ketamine, pentobarbital, opioids as morphine milligram equivalents) and continuous neuromuscular blockade (`cisatracurium`, `vecuronium`, `rocuronium`).

### 8. `medication_admin_intermittent`

| Column               | Description                       |
|----------------------|-----------------------------------|
| `hospitalization_id` | Unique hospitalization identifier |
| `admin_dttm`         | Administration date/time          |
| `med_category`       | Medication category               |
| `med_group`          | Medication group                  |
| `med_dose`           | Dose amount                       |
| `med_dose_unit`      | Dose unit                         |

Used for intermittent (push) paralytics and IMV start-time correction.

### 9. `respiratory_support`

| Column               | Description                       |
|----------------------|-----------------------------------|
| `hospitalization_id` | Unique hospitalization identifier |
| `recorded_dttm`      | Recorded date/time                |
| `device_category`    | Respiratory device category       |
| `mode_category`      | Ventilation mode                  |
| `tracheostomy`       | Flag for tracheostomy presence    |
| `fio2_set`           | FiO2 setting                      |
| `peep_set`           | PEEP setting                      |
| `tidal_volume_set`   | Tidal volume setting              |

Used to define IMV episodes, tracheostomy, and reintubation.

### 10. `patient_assessments`

| Column                | Description                       |
|-----------------------|-----------------------------------|
| `hospitalization_id`  | Unique hospitalization identifier |
| `recorded_dttm`       | Recorded date/time                |
| `assessment_category` | Assessment category               |
| `numerical_value`     | Numerical assessment value        |
| `categorical_value`   | Categorical assessment value      |

**Required `assessment_category` values:** `rass`, `gcs_total`

RASS values recorded as numbers or as text (e.g., "-2 Light sedation") are parsed to −5 to +4; other values are dropped.

### 11. `microbiology_nonculture`

| Column               | Description                       |
|----------------------|-----------------------------------|
| `hospitalization_id` | Unique hospitalization identifier |
| `collect_dttm`       | Specimen collection date/time     |
| `organism_category`  | Organism category (`sars_cov2`)   |
| `result_category`    | Result (`detected`)               |

Used for the COVID-19 flags (positive SARS-CoV-2 test from 14 days before IMV start through discharge, or ICD-10 U07.1). The code writes how each site records SARS-CoV-2 results to the audit folder; check that "detected" is the right positive value at your site.


## Cohort Identification

The cohort includes adults receiving IMV in the ICU:

1. **Age**: 18 years or older at admission
2. **IMV episodes**: built from `respiratory_support`; observation starts at IMV start
3. **Study period**: hospitalizations discharged before 1 January 2026 
4. **Location**: no more than 4 hours outside the ICU after IMV start (patients excluded only for this reason are kept, flagged, for a sensitivity analysis)
5. **RASS**: at least one RASS documented within 8 hours of IMV start
6. **Language**: known language preference (`language_category`)
7. **Primary cohort**: English- and Spanish-language preference, in ICUs that treated at least one patient with Spanish-language preference

### Primary outcome

Percent of hours 4–47 of IMV (up to 44 hours) spent in deep sedation, defined as the lowest RASS in the hour ≤ −3. RASS is carried forward between assessments; the value at IMV start is imputed as −5 (−1 in a sensitivity analysis) until the first charted RASS. Hours 0–3 are excluded. Hours after extubation or death do not count.

### Analysis

- **Primary**: site-level linear regression with ICU fixed effects, adjusted for age, sex, race, BMI, Elixhauser score, social vulnerability score, LAPS2, and calendar year. Site estimates are pooled at the coordinating center with random-effects meta-analysis.
- **Secondary outcomes**: 28-day ventilator-free days, total IMV hours, tracheostomy, in-hospital mortality, reintubation.
- **Sensitivity and subgroup analyses**: include alternative outcome windows (72 hours, completed 48 hours) and imputation; overlap-weighted propensity analysis; individual Elixhauser comorbidities; adjustment for COVID-19; pandemic era; excluding cardiothoracic ICUs and cardiac surgery; excluding neurological ICUs and continuous neuromuscular blockade; and hospital-level multilevel models.

## Expected Results

Output files are written under the directory specified by `local_dir` in the config file.

All files to share are in `output/FINAL_DATA_UPLOAD_ME`. **Only aggregate results are written there; counts from 1 to 9 are shown as "<10".**

| Folder | Contents |
|--------|----------|
| `cohort_characteristics/` | Cohort flow, hospitalizations by language and year or era, ICU and IMV counts, hospital language counts |
| `sedation_project/final_tables/` | Table 1 and Table 2 (descriptive and comparison files), by language group |
| `sedation_project/final_data/` | Primary and secondary model coefficients, and the results registry (`<site>_results_registry.csv`) listing every analysis and its status |
| `sedation_project/final_data/descriptive/` | Outcome histogram bins, RASS documentation, era counts, procedural-stay summaries |
| `sedation_project/final_data/sensitivity_analyses/`, `subgroup_analyses/`, `secondary_analyses/`, `exploratory_analyses/` | Model coefficients for each analysis |
| `sedation_project/final_data/revision_analyses/` | Analyses added for the revision |
| `sedation_project/final_data/heterogeneity/` | Hospital- and ICU-level estimates and site characteristics |
| `measurements_project/` | Measurements project tables, model outputs, and DLMM export |
| `audit/` | Data quality checks: exclusions by language, CONSORT flow, SARS-CoV-2 result mapping, cardiac-surgery code search, RASS imputation |

Protected intermediate files (patient-level data) are written to `intermediate_data_DO_NOT_UPLOAD` and **must not be shared**.

## Prerequisites

- **R**: version 4.0 or higher recommended
- **R packages** (installed automatically if missing):

```r
packages <- c("data.table", "dplyr", "lubridate", "arrow", "yaml", "rprojroot", "MASS",
              "lmtest", "sandwich", "lme4", "performance", "pROC", "ggplot2", "zoo")
optional <- c("ResourceSelection", "fst")
```

## Instructions

### 1. Configure the config file

Copy the template and fill in site-specific paths:

```bash
cp config/language_sedation_config_template.yaml config/language_sedation_config.yaml
```

```yaml
data_dir: ""       # Path to CLIF tables - must end with "/"
local_dir: ""      # Path to project directory - must end with "/"
file_type: ".parquet"
institution: "YourInstitution"
time_zone: "America/New_York"   # Your site's local timezone
```

- `data_dir`: Path to your CLIF 2.1 parquet (or CSV) tables
- `local_dir`: Where intermediate and final results will be saved
- `file_type`: File extension of your CLIF tables (e.g. `.parquet` or `.csv`)
- `institution`: Your site name, used for labeling output files
- `time_zone`: Your site's local timezone

### 2. Run the scripts in RStudio, in order

1. `code/00_cohort_id_1116.Rmd`: builds the cohort and the analytic file
2. `code/01_analysis_1116.Rmd`: deep sedation analyses
3. `code/02_measurements_analysis_1116.Rmd`: measurements project

> **Note:** 256GB of RAM is recommended for sites with larger databases; 128GB may be sufficient for smaller databases.

`00_cohort_id` saves the cohort and LAPS2 steps to `intermediate_data_DO_NOT_UPLOAD` and reuses them on later runs when the settings and code version are unchanged. Delete those files to force a full rebuild.

If an input for an optional analysis is missing at your site, the analysis is skipped rather than stopping the script. It is listed in `<site>_input_availability.csv` and in the results registry.

### 3. Upload results to Box

Upload the contents of `output/FINAL_DATA_UPLOAD_ME` to the shared Box folder: https://app.box.com/folder/438119061452

## Questions

Please contact **Alex Ortiz on Slack** with any questions or issues.