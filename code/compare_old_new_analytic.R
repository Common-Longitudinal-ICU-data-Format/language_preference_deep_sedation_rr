################################################################################
# compare_old_new_analytic.R
# Compares a site's analytic file from the ORIGINAL submission (deep_sedation_language_final) with the one from
# the REVISION pipeline (language_preference_deep_sedation_rr), to explain why the site's estimate moved.
#
# Run at the site, from anywhere inside the revision project:   source("code/compare_old_new_analytic.R")
# Both projects must sit under the same parent folder (or set old_root / new_root by hand below).
#
# Reads only the two local analytic files. Writes AGGREGATE tables only (counts of 1-9 shown as "<10"; means
# over fewer than 10 patients blanked) to output/FINAL_DATA_UPLOAD_ME/old_vs_new_comparison/ in the revision
# project. Those files can be sent to the coordinating site. Nothing patient-level is written.
#
# What it answers:
#   1. How many hospitalizations are in both files, only the old one, only the new one (by language)?
#   2. For the same hospitalizations: did language, the outcome, begin_obs or the covariates change?
#   3. How much of the change in the SLP estimate comes from (a) patients dropped, (b) covariate/ICU changes,
#      (c) the new outcome definition, (d) patients added?  (primary-model specification, linear model)
################################################################################

suppressPackageStartupMessages({ library(data.table); library(yaml); library(rprojroot) })

# ---- 0. Settings (edit only if the automatic search fails) ----------------------------------------------------
old_project_name <- "deep_sedation_language_final"
new_project_name <- "language_preference_deep_sedation_rr"
old_root <- NULL   # e.g. "/home/me/my_projects/deep_sedation_language_final"
new_root <- NULL
MIN_CELL <- 10

# ---- 1. Find the two projects, their configs and analytic files -----------------------------------------------
find_project <- function(name) {
  r <- tryCatch(find_root(has_dir(name)), error = function(e) NULL)       # searches upward from the working dir
  if (!is.null(r)) return(file.path(r, name))
  for (up in c("..", "../..", "../../..")) {                              # or a sibling of a parent folder
    p <- normalizePath(file.path(getwd(), up, name), mustWork = FALSE)
    if (dir.exists(p)) return(p)
  }
  stop("Could not find the project folder '", name, "'. Set old_root / new_root at the top of this script.")
}
read_project_config <- function(root) {
  f <- list.files(file.path(root, "config"), pattern = "\\.ya?ml$", full.names = TRUE)
  for (x in f) { cfg <- tryCatch(read_yaml(x), error = function(e) NULL)
  if (!is.null(cfg$institution)) return(cfg) }
  stop("No config with an 'institution' entry in ", file.path(root, "config"))
}
find_analytic <- function(root, cfg) {
  dirs <- unique(c(file.path(root, "intermediate_data_DO_NOT_UPLOAD"),
                   if (!is.null(cfg$local_dir)) file.path(cfg$local_dir, "intermediate_data_DO_NOT_UPLOAD")))
  for (d in dirs[dir.exists(dirs)]) {
    f <- list.files(d, pattern = "^analytic_file.*\\.(parquet|csv)$", full.names = TRUE)
    if (length(f) > 1) f <- f[grepl(cfg$institution, basename(f), fixed = TRUE)]
    if (length(f)) return(f[which.max(file.mtime(f))])
  }
  stop("No analytic_file*.parquet in: ", paste(dirs, collapse = " ; "))
}
read_any <- function(f) as.data.table(if (grepl("\\.parquet$", f)) arrow::read_parquet(f) else fread(f))

`%||%` <- function(a, b) if (is.null(a)) b else a
old_root <- old_root %||% find_project(old_project_name)
new_root <- new_root %||% find_project(new_project_name)
old_cfg <- read_project_config(old_root); new_cfg <- read_project_config(new_root)
institution <- new_cfg$institution
old_file <- find_analytic(old_root, old_cfg); new_file <- find_analytic(new_root, new_cfg)
message("Institution: ", institution, "\n  old: ", old_file, "  (", format(file.mtime(old_file), "%Y-%m-%d"), ")",
        "\n  new: ", new_file, "  (", format(file.mtime(new_file), "%Y-%m-%d"), ")")

out_dir <- file.path(new_cfg$local_dir %||% new_root, "output", "FINAL_DATA_UPLOAD_ME", "old_vs_new_comparison")
if (!dir.exists(dirname(dirname(out_dir)))) out_dir <- file.path(new_root, "output", "FINAL_DATA_UPLOAD_ME", "old_vs_new_comparison")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
save_out <- function(dt, name) fwrite(dt, file.path(out_dir, paste0(institution, "_old_vs_new_", name, ".csv")))

# ---- 2. Read and standardize ------------------------------------------------------------------------------------
prep <- function(dt) {
  dt <- copy(dt)
  if (!"language_category" %in% names(dt)) stop("language_category is missing from ", deparse(substitute(dt)))
  dt[, language_category := tolower(trimws(as.character(language_category)))]
  dt[, lang := fcase(language_category == "english", "english", language_category == "spanish", "spanish",
                     !is.na(language_category) & language_category != "", "other", default = NA_character_)]
  dt[, hospitalization_id := as.character(hospitalization_id)]
  if ("observation_year" %in% names(dt)) dt[, observation_year := as.numeric(as.character(observation_year))]
  if ("sens_only_icu_late" %in% names(dt)) dt <- dt[!(sens_only_icu_late %in% TRUE)]   # R4.7 carry-forward rows
  dt
}
old <- prep(read_any(old_file)); new <- prep(read_any(new_file))

# ---- 3. Masking helpers -----------------------------------------------------------------------------------------
mask_n <- function(n) ifelse(is.na(n), NA_character_, ifelse(n > 0 & n < MIN_CELL, "<10", format(n, big.mark = "", scientific = FALSE)))
blank_if_small <- function(dt, n_col, cols) { dt[get(n_col) < MIN_CELL, (cols) := NA]; dt }

# ---- 4. Match the same hospitalizations in the two files ---------------------------------------------------------
# A data refresh can re-key hospitalization_id / patient_id and re-draw the date shift, so a shared ID is NOT proof
# of the same hospitalization. Every match is therefore checked against fields that should not change between
# extracts (age, sex, length of stay), and three keys are tried in order:
#   1. hospitalization_id            (kept only if the pair agrees on age, sex and length of stay)
#   2. patient_id + admission date   (same check)
#   3. fingerprint: age + sex + race + ethnicity + length of stay in hours, used only when unique in both files
as_time <- function(x) if (inherits(x, "POSIXt")) x else suppressWarnings(as.POSIXct(as.character(x), tz = "UTC"))
add_fp <- function(dt) {
  g <- function(v) if (v %in% names(dt)) dt[[v]] else rep(NA, nrow(dt))
  dt[, `:=`(fp_age = as.integer(round(as.numeric(g("age_at_admission")))),
            fp_sex = tolower(as.character(g("sex_category"))),
            fp_race = tolower(as.character(g("race_category"))),
            fp_eth = tolower(as.character(g(if ("ethnicity_category" %in% names(dt)) "ethnicity_category" else "ethnicity_category_final"))),
            fp_los = if (all(c("admission_dttm", "discharge_dttm") %in% names(dt)))
              round(as.numeric(difftime(as_time(discharge_dttm), as_time(admission_dttm), units = "hours"))) else NA_real_,
            fp_adm_date = if ("admission_dttm" %in% names(dt)) as.Date(as_time(admission_dttm)) else as.Date(NA))]
  dt
}
old <- add_fp(old); new <- add_fp(new)
agree <- function(oid, nid) {                       # TRUE when a candidate pair looks like the same hospitalization
  o <- old[match(oid, hospitalization_id)]; n <- new[match(nid, hospitalization_id)]
  ok_age <- is.na(o$fp_age) | is.na(n$fp_age) | abs(o$fp_age - n$fp_age) <= 1
  ok_sex <- is.na(o$fp_sex) | is.na(n$fp_sex) | o$fp_sex == n$fp_sex
  ok_los <- is.na(o$fp_los) | is.na(n$fp_los) | abs(o$fp_los - n$fp_los) <= 2
  ok_age & ok_sex & ok_los
}
# 1. hospitalization_id
cand1 <- intersect(old$hospitalization_id, new$hospitalization_id)
ok1 <- if (length(cand1)) agree(cand1, cand1) else logical(0)
pairs <- data.table(old_id = cand1[ok1], new_id = cand1[ok1], key_type = "hospitalization_id")
n_id_rejected <- sum(!ok1)
if (length(cand1) && mean(ok1) < 0.9)
  message("Only ", round(100 * mean(ok1)), "% of the ", length(cand1), " shared hospitalization_ids agree on age, sex and length of stay: ",
          "the IDs were probably re-keyed between extracts. Unverified ID matches are discarded.")
# 2. patient_id + admission date
if (all(c("patient_id", "admission_dttm") %in% names(old)) && all(c("patient_id", "admission_dttm") %in% names(new))) {
  k_old <- old[!hospitalization_id %in% pairs$old_id, .(old_id = hospitalization_id, patient_id = as.character(patient_id), d = fp_adm_date)]
  k_new <- new[!hospitalization_id %in% pairs$new_id, .(new_id = hospitalization_id, patient_id = as.character(patient_id), d = fp_adm_date)]
  c2 <- unique(unique(merge(k_old, k_new, by = c("patient_id", "d")), by = "old_id"), by = "new_id")
  if (nrow(c2)) { c2 <- c2[agree(old_id, new_id)]; pairs <- rbind(pairs, c2[, .(old_id, new_id, key_type = "patient + admission date")]) }
}
# 3. fingerprint (no IDs or dates involved, so it survives re-keying and a new date shift)
fp_cols <- c("fp_age", "fp_sex", "fp_race", "fp_eth", "fp_los")
fp_ok <- function(dt) dt[!is.na(fp_age) & !is.na(fp_sex) & !is.na(fp_los)]
if (any(!is.na(old$fp_los)) && any(!is.na(new$fp_los))) {
  f_old <- fp_ok(old[!hospitalization_id %in% pairs$old_id])[, c("hospitalization_id", fp_cols), with = FALSE]
  f_new <- fp_ok(new[!hospitalization_id %in% pairs$new_id])[, c("hospitalization_id", fp_cols), with = FALSE]
  f_old <- f_old[, if (.N == 1) .SD, by = fp_cols]; f_new <- f_new[, if (.N == 1) .SD, by = fp_cols]   # unique only
  c3 <- merge(f_old, f_new, by = fp_cols, suffixes = c("_old", "_new"))
  if (nrow(c3)) pairs <- rbind(pairs, c3[, .(old_id = hospitalization_id_old, new_id = hospitalization_id_new, key_type = "age/sex/race/ethnicity/length of stay")])
}

lang_n <- function(dt, label) dt[, .(set = label, n = .N), by = lang]
overlap <- rbindlist(list(
  lang_n(old, "old file, total"),
  lang_n(new, "new file, total"),
  lang_n(new[hospitalization_id %in% pairs[key_type == "hospitalization_id", new_id]], "matched: hospitalization_id (verified)"),
  lang_n(new[hospitalization_id %in% pairs[key_type == "patient + admission date", new_id]], "matched: patient_id + admission date (verified)"),
  lang_n(new[hospitalization_id %in% pairs[key_type == "age/sex/race/ethnicity/length of stay", new_id]], "matched: age/sex/race/ethnicity/length of stay"),
  lang_n(new[hospitalization_id %in% setdiff(cand1, pairs$new_id)], "shared hospitalization_id but a different hospitalization (rejected)"),
  lang_n(old[!hospitalization_id %in% pairs$old_id], "old only (unmatched)"),
  lang_n(new[!hospitalization_id %in% pairs$new_id], "new only (unmatched)")
), use.names = TRUE, fill = TRUE)
set_order <- unique(overlap$set)
overlap <- dcast(overlap, set ~ lang, value.var = "n", fill = 0)
overlap <- overlap[order(match(set, set_order))]
overlap[, total := rowSums(.SD), .SDcols = setdiff(names(overlap), "set")]
num_cols <- setdiff(names(overlap), "set")
overlap_out <- copy(overlap)[, (num_cols) := lapply(.SD, mask_n), .SDcols = num_cols]
save_out(overlap_out, "overlap")
pct_matched <- 100 * nrow(pairs) / nrow(new)
if (pct_matched < 50) message("Only ", round(pct_matched), "% of the new file could be matched to the old one. Sections 5-8 describe ",
                              "that matched subset only; if it is small, rely on the overlap table and models 1 and 5.")

O <- old[pairs, on = c(hospitalization_id = "old_id")]; setnames(O, "hospitalization_id", "old_id")
N <- new[pairs, on = c(hospitalization_id = "new_id")]; setnames(N, "hospitalization_id", "new_id")
setkey(O, old_id); setkey(N, new_id)
O <- O[pairs$old_id]; N <- N[pairs$new_id]                                       # same row order = same pair

# ---- 5. Same hospitalizations: did language change? ----------------------------------------------------------------
lang_x <- data.table(old_lang = O$lang, new_lang = N$lang)[, .N, by = .(old_lang, new_lang)][order(old_lang, new_lang)]
lang_x[, N := mask_n(N)]
save_out(lang_x, "language_crosstab_matched")

# ---- 6. Same hospitalizations: what changed, variable by variable ------------------------------------------------
is_time <- function(x) inherits(x, "POSIXt") || (is.character(x) && mean(grepl("^\\d{4}-\\d{2}-\\d{2}[ T]\\d{2}:\\d{2}", head(x[!is.na(x)], 50))) > 0.9)
has_adm <- "admission_dttm" %in% names(O) && "admission_dttm" %in% names(N)
if (has_adm) { O_adm <- as_time(O$admission_dttm); N_adm <- as_time(N$admission_dttm) }
skip <- c("hospitalization_id", "patient_id", "old_id", "new_id", "key_type", "lang", "fp_age", "fp_sex", "fp_race", "fp_eth", "fp_los", "fp_adm_date")
common <- setdiff(intersect(names(O), names(N)), skip)
var_change <- rbindlist(lapply(common, function(v) {
  a <- O[[v]]; b <- N[[v]]
  ok <- !is.na(a) & !is.na(b)
  base <- data.table(variable = v, n_pairs = length(a), pct_missing_old = 100 * mean(is.na(a)), pct_missing_new = 100 * mean(is.na(b)))
  if (is_time(a) || is_time(b)) {
    a <- as_time(a); b <- as_time(b); ok <- !is.na(a) & !is.na(b)
    rel <- v != "admission_dttm" && has_adm                      # relative to admission: immune to a new date shift
    d <- if (rel) as.numeric(difftime(b, N_adm, units = "hours")) - as.numeric(difftime(a, O_adm, units = "hours"))
    else as.numeric(difftime(b, a, units = "hours"))
    d <- d[ok]
    return(cbind(base, type = "datetime", pct_changed = 100 * mean(abs(d) > 1 / 60, na.rm = TRUE), mean_old = NA_real_, mean_new = NA_real_,
                 mean_change = mean(d, na.rm = TRUE), median_change = median(d, na.rm = TRUE),
                 note = if (rel) "hours after admission, new minus old" else "absolute shift in hours (includes any change in date shifting)"))
  }
  if (is.numeric(a) && is.numeric(b)) {
    d <- b[ok] - a[ok]
    return(cbind(base, type = "numeric", pct_changed = 100 * mean(abs(d) > 1e-6), mean_old = mean(a[ok]), mean_new = mean(b[ok]),
                 mean_change = mean(d), median_change = median(d), note = NA_character_))
  }
  a <- tolower(trimws(as.character(a))); b <- tolower(trimws(as.character(b)))
  cbind(base, type = "categorical", pct_changed = 100 * mean(a[ok] != b[ok]), mean_old = NA_real_, mean_new = NA_real_,
        mean_change = NA_real_, median_change = NA_real_, note = NA_character_)
}), fill = TRUE)
var_change <- var_change[order(-pct_changed)]
var_change[, n_pairs := mask_n(n_pairs)]
save_out(var_change, "variable_changes_matched")
cols_only <- data.table(only_in = c(rep("old", length(setdiff(names(old), names(new)))), rep("new", length(setdiff(names(new), names(old))))),
                        column = c(setdiff(names(old), names(new)), setdiff(names(new), names(old))))
save_out(cols_only, "columns_only_in_one_file")

# ---- 7. Same hospitalizations: outcome and begin_obs change by language ------------------------------------------
oc <- data.table(lang = N$lang, pds_old = O$percent_deep_sedation_48, pds_new = N$percent_deep_sedation_48)
if ("begin_obs" %in% names(O) && "begin_obs" %in% names(N) && has_adm)   # begin_obs relative to admission, new minus old
  oc[, begin_obs_shift_h := as.numeric(difftime(as_time(N$begin_obs), N_adm, units = "hours")) - as.numeric(difftime(as_time(O$begin_obs), O_adm, units = "hours"))]
if ("time_to_first_rass" %in% names(O) && "time_to_first_rass" %in% names(N)) oc[, `:=`(ttfr_old = O$time_to_first_rass, ttfr_new = N$time_to_first_rass)]
oc_sum <- oc[!is.na(lang) & !is.na(pds_old) & !is.na(pds_new), c(list(
  n = .N, mean_pds_old = mean(pds_old), mean_pds_new = mean(pds_new), mean_change = mean(pds_new - pds_old),
  sd_change = sd(pds_new - pds_old), pct_changed_gt_1pp = 100 * mean(abs(pds_new - pds_old) > 1)),
  if ("begin_obs_shift_h" %in% names(oc)) list(mean_begin_obs_shift_h = mean(begin_obs_shift_h, na.rm = TRUE),
                                               pct_begin_obs_moved = 100 * mean(abs(begin_obs_shift_h) > 1 / 60, na.rm = TRUE)),
  if ("ttfr_old" %in% names(oc)) list(mean_time_to_first_rass_old = mean(ttfr_old, na.rm = TRUE), mean_time_to_first_rass_new = mean(ttfr_new, na.rm = TRUE))
), by = lang][order(lang)]
oc_sum <- blank_if_small(oc_sum, "n", setdiff(names(oc_sum), c("lang", "n")))
oc_sum[, n := mask_n(n)]
save_out(oc_sum, "outcome_change_matched_by_language")

# Patients only in one file: how do they differ?
desc_set <- function(dt, label) dt[!is.na(lang), c(list(set = label, n = .N, mean_pds = mean(percent_deep_sedation_48, na.rm = TRUE)),
                                                   if ("laps2" %in% names(dt)) list(mean_laps2 = mean(as.numeric(laps2), na.rm = TRUE)),
                                                   if ("run_hrs" %in% names(dt)) list(mean_run_hrs = mean(as.numeric(run_hrs), na.rm = TRUE))), by = lang]
only_sets <- rbindlist(list(desc_set(old[!hospitalization_id %in% pairs$old_id], "old only"),
                            desc_set(new[!hospitalization_id %in% pairs$new_id], "new only"),
                            desc_set(N, "in both (new values)")), fill = TRUE)
only_sets <- blank_if_small(only_sets, "n", setdiff(names(only_sets), c("set", "lang", "n")))[order(set, lang)]
only_sets[, n := mask_n(n)]
save_out(only_sets, "old_only_vs_new_only")

# ---- 8. Decomposition of the change in the SLP estimate (primary-model specification) ----------------------------
covs_all <- c("race_category", "age_category", "sex_category", "bmi", "factor(hospital_icu_id)",
              "elixhauser_score", "SVM_SCORE", "laps2", "factor(observation_year)")
primary_like <- function(dt) {                                  # English/Spanish; ICUs that treated >= 1 SLP patient
  d <- dt[lang %in% c("english", "spanish")]
  if ("hospital_icu_id" %in% names(d)) d <- d[hospital_icu_id %in% d[lang == "spanish", unique(hospital_icu_id)]]
  d[, lang_cat_6 := factor(lang, levels = c("english", "spanish"))]
  d
}
fit_slp <- function(d, label, outcome = "percent_deep_sedation_48") {
  covs <- covs_all[gsub("factor\\(|\\)", "", covs_all) %in% names(d)]
  covs <- covs[vapply(covs, function(cv) { v <- gsub("factor\\(|\\)", "", cv); uniqueN(d[[v]][!is.na(d[[v]])]) > 1 }, TRUE)]
  f <- reformulate(c("lang_cat_6", covs), response = outcome)
  m <- tryCatch(lm(f, data = d), error = function(e) NULL)
  if (is.null(m) || !"lang_cat_6spanish" %in% names(coef(m))) return(data.table(model = label, estimate = NA_real_))
  s <- summary(m)$coefficients["lang_cat_6spanish", ]
  used <- d[as.integer(rownames(model.frame(m)))]
  data.table(model = label, estimate = s[1], ci_lower = s[1] - 1.96 * s[2], ci_upper = s[1] + 1.96 * s[2], p_value = s[4],
             n_elp = sum(used$lang == "english"), n_slp = sum(used$lang == "spanish"),
             covariates = paste(gsub("factor\\(|\\)", "", covs), collapse = ", "))
}
P_old <- primary_like(old); P_new <- primary_like(new)
matched <- pairs[old_id %in% P_old$hospitalization_id & new_id %in% P_new$hospitalization_id]
M_old <- P_old[match(matched$old_id, hospitalization_id)]
M_new <- P_new[match(matched$new_id, hospitalization_id)]
M_swap <- copy(M_new)[, percent_deep_sedation_48 := M_old$percent_deep_sedation_48]   # new covariates, OLD outcome

dec <- rbindlist(list(
  fit_slp(P_old,  "1. Old file, old primary cohort"),
  fit_slp(M_old,  "2. Old file, only patients also in the new cohort"),
  fit_slp(M_swap, "3. Same patients, new covariates and ICU ids, OLD outcome"),
  fit_slp(M_new,  "4. Same patients, new covariates, NEW outcome"),
  fit_slp(P_new,  "5. New file, new primary cohort")), fill = TRUE)
dec[, step_change := estimate - shift(estimate)]
dec[, explains := c("starting point (original submission specification)",
                    "patients dropped by the new pipeline",
                    "covariate and ICU changes for the same patients",
                    "new outcome definition (begin_obs, windows) for the same patients",
                    "patients added by the new pipeline")]
dec_out <- copy(dec)[, `:=`(n_elp = mask_n(n_elp), n_slp = mask_n(n_slp))]
save_out(dec_out, "decomposition")

# ---- 9. Console summary --------------------------------------------------------------------------------------------
cat("\n================ OLD vs NEW analytic file:", institution, "================\n")
print(overlap_out)
cat("\nLanguage of the same hospitalizations, old (rows) vs new:\n"); print(lang_x)
cat("\nOutcome change for the same hospitalizations, by language:\n"); print(oc_sum)
cat("\nVariables that changed most for the same hospitalizations:\n")
print(var_change[1:min(15, .N), .(variable, type, pct_changed = round(pct_changed, 1), mean_old = signif(mean_old, 4),
                                  mean_new = signif(mean_new, 4), mean_change = signif(mean_change, 3), pct_missing_old = round(pct_missing_old, 1),
                                  pct_missing_new = round(pct_missing_new, 1))])
cat("\nWhere the change in the SLP estimate comes from (percentage points):\n")
print(dec_out[, .(model, estimate = round(estimate, 2), ci = sprintf("%.2f to %.2f", ci_lower, ci_upper), n_elp, n_slp,
                  step_change = round(step_change, 2), explains)])
cat("\nNote: estimates use lm() with the primary-model covariates available in each file. Model 1 may differ a little\n",
    "from the submitted site estimate and model 5 from the new results registry; the steps between them are what matter.\n",
    "Aggregate tables written to: ", out_dir, "\n", sep = "")
