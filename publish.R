#!/usr/bin/env Rscript

# Render from certified private-run outputs or an already released aggregate-only
# public checkout. Pass --publish only after separate human review.

args <- commandArgs(trailingOnly = TRUE)
publish <- "--publish" %in% args
sync_only <- "--sync" %in% args
aggregate_only <- "--aggregate-only" %in% args
privacy_gate_fixture <- "--privacy-gate-fixture" %in% args
if (aggregate_only && (publish || sync_only)) stop("Publication-repository sync is unavailable in aggregate-only mode.", call. = FALSE)
if (publish && sync_only) stop("Choose either --sync or --publish.", call. = FALSE)
project_dir <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
public_results <- c(
  "cohort_flow.csv", "crude_weighted_risks.csv", "adjusted_risks.csv", "adjusted_contrasts.csv",
  "table1.csv", "sensitivity_results.csv", "e_value.csv", "subgroup_results.csv",
  "model_main.csv", "model_conditional.csv", "missingness_flow.csv", "complete_case_flow.csv",
  "transfer_exclusions.csv", "first_readmission_mortality.csv", "secondary_outcomes.csv",
  "utilization.csv", "cost_availability.csv", "model_adjusted_risks.csv",
  "model_adjusted_contrasts.csv", "model_coefficients.csv", "sensitivity_adjusted_risks.csv",
  "sensitivity_adjusted_contrasts.csv", "analysis_summary.csv"
)
public_source_files <- c("_quarto.yml", "quarto/index.qmd", "REPRODUCING.md", "README.md", "publish.R")
assert_no_forbidden_design_text <- function(tables) {
  forbidden_design_tokens <- c(
    "design[._ -]*psu", "design[._ -]*strat(?:um|a)",
    "index_HOSP_NRD", "index_NRD_STRATUM", "hospital_id", "hosp_nrd", "nrd_stratum",
    "(?:^|[^[:alnum:]_])psu(?:_id|_identifier)?(?:$|[^[:alnum:]_])",
    "(?:^|[^[:alnum:]_])strat(?:um|a)(?:_id|_identifier)?(?:$|[^[:alnum:]_])",
    "(?:^|[^[:alnum:]_])(?:cluster|design_cluster)(?:_id)?(?:$|[^[:alnum:]_])",
    "(?:^|[^[:alnum:]_])sampling_unit(?:_id)?(?:$|[^[:alnum:]_])"
  )
  public_text_cells <- unlist(lapply(tables, function(data) {
    text_columns <- vapply(data, function(column) is.character(column) || is.factor(column), logical(1))
    unlist(data[text_columns], use.names = FALSE)
  }), use.names = FALSE)
  if (!length(public_text_cells)) return(invisible(TRUE))
  leaked_design_text <- vapply(public_text_cells, function(value) {
    any(vapply(forbidden_design_tokens, grepl, logical(1), x = value,
               ignore.case = TRUE, perl = TRUE))
  }, logical(1))
  if (any(leaked_design_text)) {
    stop("Public aggregate text contains a forbidden internal design identifier.", call. = FALSE)
  }
  invisible(TRUE)
}
if (privacy_gate_fixture) {
  assert_no_forbidden_design_text(list(safe = data.frame(note = "converged", stringsAsFactors = FALSE)))
  forbidden_fixture_labels <- c("design_psu", "design_stratum", "index_HOSP_NRD", "stratum_id")
  rejected <- vapply(forbidden_fixture_labels, function(label) {
    tryCatch({
      assert_no_forbidden_design_text(list(analysis_summary = data.frame(
        model = "primary_enriched", diagnostic_text = label, stringsAsFactors = FALSE
      )))
      FALSE
    }, error = function(e) grepl("forbidden internal design identifier", conditionMessage(e), fixed = TRUE))
  }, logical(1))
  if (!all(rejected)) stop("Privacy-gate fixture did not reject every forbidden design label.", call. = FALSE)
  message("PASS: safe diagnostic text is accepted and leaked design identifiers are rejected.")
  quit(status = 0L)
}
if (length(public_results) != 23L || anyDuplicated(public_results)) {
  stop("The public aggregate release must contain exactly 23 unique CSVs.", call. = FALSE)
}
required_public <- file.path("results", public_results)
missing <- required_public[!file.exists(file.path(project_dir, required_public))]
if (length(missing)) stop("Missing required public aggregate results: ", paste(missing, collapse = ", "), call. = FALSE)
if (aggregate_only) {
  public_result_entries <- list.files(file.path(project_dir, "results"), recursive = FALSE,
                                      all.files = TRUE, no.. = TRUE)
  if (!setequal(public_result_entries, public_results)) {
    stop("Aggregate-only mode requires a results directory containing exactly the 23 released CSVs.", call. = FALSE)
  }
}

if (!aggregate_only) {
  private_required <- c("scripts/01_cohort.R", "scripts/02_analysis.R", "scripts/analysis_diagnostics.R", "scripts/analysis_release.R",
                       "scripts/verify_analysis_diagnostics.R", "results/cohort_manifest.csv",
                       "results/analysis_manifest.csv", "results/small_cell_suppression_audit_summary.csv")
  missing_private <- private_required[!file.exists(file.path(project_dir, private_required))]
  if (length(missing_private)) {
    stop("Private certified rendering requires scripts and both manifests. Use --aggregate-only only for a clean public-source build.", call. = FALSE)
  }
  cohort_manifest <- utils::read.csv(file.path(project_dir, "results/cohort_manifest.csv"), stringsAsFactors = FALSE)
  analysis_manifest <- utils::read.csv(file.path(project_dir, "results/analysis_manifest.csv"), stringsAsFactors = FALSE)
  years_expected <- paste(2016:2022, collapse = ",")
  cohort_run_ids <- unique(cohort_manifest$run_id)
  analysis_run_ids <- unique(analysis_manifest$run_id)
  cohort_script_md5 <- unname(tools::md5sum(file.path(project_dir, "scripts/01_cohort.R")))
  analysis_script_md5 <- unname(tools::md5sum(file.path(project_dir, "scripts/02_analysis.R")))
  if (length(cohort_run_ids) != 1L || any(cohort_manifest$years != years_expected) ||
      any(cohort_manifest$cohort_script_md5 != cohort_script_md5)) {
    stop("Cohort manifest does not certify the current complete seven-year cohort build.", call. = FALSE)
  }
  if (length(analysis_run_ids) != 1L || any(analysis_manifest$years != years_expected) ||
      any(analysis_manifest$cohort_run_id != cohort_run_ids[[1]]) ||
      any(analysis_manifest$cohort_script_md5 != cohort_script_md5) ||
      any(analysis_manifest$analysis_script_md5 != analysis_script_md5)) {
    stop("Analysis manifest does not match the current cohort and analysis scripts.", call. = FALSE)
  }
  audit_fields <- c("small_cell_suppression_audit_passed", "crossrow_release_audit_passed")
  if (any(!audit_fields %in% names(analysis_manifest)) || anyNA(analysis_manifest[audit_fields]) ||
      any(!vapply(analysis_manifest[audit_fields], function(x) all(tolower(as.character(x)) == "true"), logical(1)))) {
    stop("Analysis manifest does not certify passed small-cell and cross-row release audits.", call. = FALSE)
  }
  verify_manifest_outputs <- function(manifest, label, source_outputs_replaced_by_analysis = character()) {
    if (anyDuplicated(manifest$output) || any(basename(manifest$output) != manifest$output)) {
      stop(label, " manifest has duplicate or unsafe output names.", call. = FALSE)
    }
    output_paths <- file.path(project_dir, "results", manifest$output)
    if (any(!file.exists(output_paths))) stop(label, " manifest lists missing outputs.", call. = FALSE)
    actual_md5 <- unname(tools::md5sum(output_paths))
    checksum_mismatch <- actual_md5 != manifest$output_md5
    allowed_replacement <- manifest$output %in% source_outputs_replaced_by_analysis
    if (any(checksum_mismatch & !allowed_replacement)) {
      stop(label, " outputs do not match their manifest checksums.", call. = FALSE)
    }
    invisible(manifest$output)
  }
  # The analysis rewrites these two cohort flow aggregates with suppression
  # applied; its own manifest below certifies the current released versions.
  cohort_outputs <- verify_manifest_outputs(cohort_manifest, "Cohort",
    c("cohort_flow.csv", "transfer_exclusions.csv"))
  analysis_outputs <- verify_manifest_outputs(analysis_manifest, "Analysis")
  source(file.path(project_dir, "scripts/analysis_release.R"), local = TRUE)
  diagnostics_hashes <- c("analysis_diagnostics_script_md5", "verify_analysis_diagnostics_script_md5")
  diagnostic_paths <- c("scripts/analysis_diagnostics.R", "scripts/verify_analysis_diagnostics.R")
  if (any(!diagnostics_hashes %in% names(analysis_manifest)) || anyNA(analysis_manifest[diagnostics_hashes]) ||
      any(!vapply(seq_along(diagnostics_hashes), function(i) {
        all(analysis_manifest[[diagnostics_hashes[[i]]]] ==
              unname(tools::md5sum(file.path(project_dir, diagnostic_paths[[i]]))))
      }, logical(1)))) {
    stop("Analysis manifest does not certify the current diagnostic scripts.", call. = FALSE)
  }
  if (!"analysis_release_script_md5" %in% names(analysis_manifest) || anyNA(analysis_manifest$analysis_release_script_md5) ||
      any(analysis_manifest$analysis_release_script_md5 !=
        unname(tools::md5sum(file.path(project_dir, "scripts/analysis_release.R"))))) {
    stop("Analysis manifest does not certify the current release helper.", call. = FALSE)
  }
  if (!"analysis_model_code_md5" %in% names(analysis_manifest) || anyNA(analysis_manifest$analysis_model_code_md5) ||
      any(analysis_manifest$analysis_model_code_md5 !=
        analysis_model_code_md5(file.path(project_dir, "scripts/02_analysis.R")))) {
    stop("Analysis manifest does not certify the fitted model-code prefix.", call. = FALSE)
  }
  if (!all(c("model_execution_script_md5", "analysis_resume_mode") %in% names(analysis_manifest)) ||
      anyNA(analysis_manifest$model_execution_script_md5) || anyNA(analysis_manifest$analysis_resume_mode) ||
      any(!analysis_manifest$analysis_resume_mode %in% c("fresh", "postfit_release_resume"))) {
    stop("Analysis manifest has incomplete model-execution provenance.", call. = FALSE)
  }
  if (any(!public_results %in% c(cohort_outputs, analysis_outputs))) {
    stop("A public aggregate output is not certified by the current manifests.", call. = FALSE)
  }
}
read_public_schema <- function(name, expected) {
  data <- utils::read.csv(file.path(project_dir, "results", name), check.names = FALSE,
                          stringsAsFactors = FALSE)
  if (!identical(names(data), expected)) {
    stop(name, " does not have its reviewed public schema.", call. = FALSE)
  }
  data
}
public_schemas <- list(
  cohort_flow.csv = c("YEAR", "eligible_first_index_n", "eligible_first_index_weighted", "first_readmitted_30d_n", "first_readmitted_30d_weighted", "second_stage_eligible_n", "second_stage_eligible_weighted"),
  crude_weighted_risks.csv = c("fragmented", "weighted_risk", "standard_error", "ci_low", "ci_high", "unweighted_n", "weighted_n"),
  adjusted_risks.csv = c("group", "adjusted_risk", "ci_low", "ci_high"),
  adjusted_contrasts.csv = c("measure", "estimate", "standard_error", "ci_low", "ci_high"),
  table1.csv = c("variable", "level", "same_hospital", "different_hospital", "standardized_difference", "same_n", "different_n", "summary_scale"),
  sensitivity_results.csv = c("analysis", "outcome", "estimate_log_odds", "standard_error", "odds_ratio", "ci_low", "ci_high", "p_value", "n"),
  e_value.csv = c("adjusted_rr", "adjusted_rr_ci_low", "e_value", "e_value_ci"),
  subgroup_results.csv = c("subgroup", "estimate_log_odds", "standard_error", "odds_ratio", "ci_low", "ci_high", "p_value", "n"),
  model_main.csv = c("term", "estimate_log_odds", "standard_error", "odds_ratio", "ci_low", "ci_high", "p_value"),
  model_conditional.csv = c("term", "estimate_log_odds", "standard_error", "odds_ratio", "ci_low", "ci_high", "p_value"),
  missingness_flow.csv = c("variable", "YEAR", "fragmentation_group", "eligible_n", "missing_n", "missing_pct"),
  complete_case_flow.csv = c("YEAR", "fragmentation_group", "second_stage_eligible_n", "complete_case_n", "excluded_missing_n", "second_stage_eligible_weighted", "complete_case_weighted", "excluded_missing_weighted"),
  transfer_exclusions.csv = c("YEAR", "stage", "entering_n", "entering_weighted", "excluded_n", "excluded_weighted", "remaining_n", "remaining_weighted"),
  first_readmission_mortality.csv = c("group", "denominator", "weighted_mortality_risk", "standard_error", "ci_low", "ci_high", "observed_status_denominator_n", "observed_status_weighted_denominator", "unknown_status_excluded_n"),
  secondary_outcomes.csv = c("outcome", "group", "estimate", "standard_error", "ci_low", "ci_high", "unweighted_n", "weighted_n", "scale"),
  utilization.csv = c("outcome", "group", "estimate", "standard_error", "ci_low", "ci_high", "unweighted_n", "weighted_n", "scale"),
  cost_availability.csv = c("measure", "status", "reason"),
  model_adjusted_risks.csv = c("model", "group", "risk", "ci_low", "ci_high", "n", "weighted_total"),
  model_adjusted_contrasts.csv = c("model", "contrast", "risk_difference", "rd_ci_low", "rd_ci_high", "risk_ratio", "rr_ci_low", "rr_ci_high", "n", "weighted_total"),
  model_coefficients.csv = c("model", "term", "estimate", "std_error", "ci_low", "ci_high", "p_value", "n", "weighted_total", "converged", "rank", "df_residual"),
  sensitivity_adjusted_risks.csv = c("analysis", "group", "risk", "ci_low", "ci_high", "n", "weighted_total"),
  sensitivity_adjusted_contrasts.csv = c("analysis", "contrast", "risk_difference", "rd_ci_low", "rd_ci_high", "risk_ratio", "rr_ci_low", "rr_ci_high", "n", "weighted_total"),
  analysis_summary.csv = c("analysis", "model", "formula", "n", "weighted_total", "psu_n", "strata_n", "design_df", "converged", "rank", "knots_age", "knots_log1p_index_los", "knot_adjustment", "dropped_terms", "sample_definition", "run_id")
)
if (!setequal(names(public_schemas), public_results)) stop("The public schema registry and file allow-list differ.", call. = FALSE)
public_tables <- lapply(names(public_schemas), function(name) read_public_schema(name, public_schemas[[name]]))
names(public_tables) <- names(public_schemas)
forbidden_identifier_patterns <- c(
  "\\bdesign_psu\\b", "\\bdesign_stratum\\b",
  "\\bindex_HOSP_NRD\\b", "\\bindex_NRD_STRATUM\\b", "\\bHOSP_NRD\\b",
  "\\bNRD_VisitLink\\b", "\\bpatient(?:_id|_identifier|_link)\\b",
  "\\bhospital(?:_id|_identifier)\\b", "\\bPSU(?:_id|_identifier)?\\b",
  "\\bstrat(?:um|a)(?:_id|_identifier)?\\b",
  "\\b(?:design_)?cluster(?:_id|_identifier)?\\b"
)
for (name in names(public_tables)) {
  data <- public_tables[[name]]
  text_columns <- data[vapply(data, function(column) is.character(column) || is.factor(column), logical(1))]
  text_values <- unlist(lapply(text_columns, as.character), use.names = FALSE)
  text_values <- text_values[!is.na(text_values)]
  if (length(text_values) && any(vapply(forbidden_identifier_patterns, function(pattern) {
    any(grepl(pattern, text_values, ignore.case = TRUE, perl = TRUE))
  }, logical(1)))) {
    stop("Public text disclosure audit found survey or hospital identifier labels in ", name, ".", call. = FALSE)
  }
}
assert_no_forbidden_design_text(public_tables)
if (!aggregate_only) {
  audit <- utils::read.csv(file.path(project_dir, "results/small_cell_suppression_audit_summary.csv"),
                           stringsAsFactors = FALSE)
  audit_schema <- c("output", "rows_checked", "count_cells_checked", "count_checks_applicable",
                    "small_count_cells", "suppression_evidence_rows", "passed")
  if (!identical(names(audit), audit_schema) || anyDuplicated(audit$output) ||
      !setequal(as.character(audit$output), public_results) ||
      anyNA(audit$passed) || any(tolower(as.character(audit$passed)) != "true")) {
    stop("Small-cell suppression evidence must cover every public table and pass before rendering.", call. = FALSE)
  }
  audit <- audit[match(public_results, audit$output), , drop = FALSE]
  table_row_counts <- vapply(public_results, function(name) nrow(public_tables[[name]]), integer(1))
  if (anyNA(audit[c("rows_checked", "count_cells_checked", "small_count_cells", "suppression_evidence_rows")]) ||
      any(audit$rows_checked != table_row_counts) ||
      any(audit$suppression_evidence_rows > audit$small_count_cells) ||
      any(audit$small_count_cells == 0 & audit$suppression_evidence_rows != 0) ||
      any(audit$count_cells_checked < 0) ||
      any(!tolower(as.character(audit$count_checks_applicable)) %in% c("true", "false"))) {
    stop("Per-table suppression audit counts do not reconcile to the public aggregate tables.", call. = FALSE)
  }
}
for (name in public_results) {
  count_fields <- grep("(^n$|_n$|count|denominator|weighted_n$|weighted_total$|_weighted$)",
                       names(public_tables[[name]]), value = TRUE, ignore.case = TRUE)
  for (field in count_fields) {
    values <- public_tables[[name]][[field]]
    if (is.numeric(values) && any(!is.finite(values) & !is.na(values))) {
      stop(name, " contains a non-finite value in count field ", field, ".", call. = FALSE)
    }
    if (is.numeric(values) && any(values < 0, na.rm = TRUE)) {
      stop(name, " contains a negative count in field ", field, ".", call. = FALSE)
    }
  }
}
primary_risks <- public_tables[["model_adjusted_risks.csv"]]
primary_risks <- primary_risks[primary_risks$model == "primary_enriched", , drop = FALSE]
primary_contrasts <- public_tables[["model_adjusted_contrasts.csv"]]
primary_contrasts <- primary_contrasts[primary_contrasts$model == "primary_enriched", , drop = FALSE]
primary_coefficients <- public_tables[["model_coefficients.csv"]]
primary_coefficients <- primary_coefficients[primary_coefficients$model == "primary_enriched", , drop = FALSE]
primary_coefficients_visible <- primary_coefficients[!is.na(primary_coefficients$term), , drop = FALSE]
primary_summary <- public_tables[["analysis_summary.csv"]]
primary_summary <- primary_summary[primary_summary$model == "primary_enriched", , drop = FALSE]
if (nrow(primary_risks) != 2L || !setequal(primary_risks$group, c("same", "different")) ||
    anyNA(primary_risks[c("risk", "ci_low", "ci_high", "n", "weighted_total")]) ||
    nrow(primary_contrasts) != 1L || primary_contrasts$contrast[[1]] != "different_vs_same" ||
    anyNA(primary_contrasts[c("risk_difference", "rd_ci_low", "rd_ci_high", "risk_ratio", "rr_ci_low", "rr_ci_high")]) ||
    !nrow(primary_coefficients_visible) ||
    any(!apply(is.na(primary_coefficients), 1L, all) & is.na(primary_coefficients$term)) ||
    anyNA(primary_coefficients_visible[c("estimate", "std_error", "ci_low", "ci_high", "p_value", "n", "weighted_total", "converged", "rank", "df_residual")]) ||
    any(tolower(as.character(primary_coefficients_visible$converged)) != "true") ||
    nrow(primary_summary) != 1L || is.na(primary_summary$formula[[1]]) || !nzchar(primary_summary$formula[[1]]) ||
    is.na(primary_summary$sample_definition[[1]]) || !nzchar(primary_summary$sample_definition[[1]]) || primary_summary$n[[1]] <= 0 ||
    tolower(as.character(primary_summary$converged[[1]])) != "true" ||
    is.na(primary_summary$run_id[[1]]) || !nzchar(primary_summary$run_id[[1]])) {
  stop("The released aggregate set lacks a complete, converged primary_enriched model contract.", call. = FALSE)
}
same_row <- primary_risks[primary_risks$group == "same", , drop = FALSE]
different_row <- primary_risks[primary_risks$group == "different", , drop = FALSE]
contrast_row <- primary_contrasts[1, , drop = FALSE]
if (any(primary_risks$risk < 0 | primary_risks$risk > 1) ||
    any(primary_risks$ci_low < 0 | primary_risks$ci_high > 1 | primary_risks$ci_low > primary_risks$risk | primary_risks$ci_high < primary_risks$risk) ||
    abs(contrast_row$risk_difference[[1]] - (different_row$risk[[1]] - same_row$risk[[1]])) > 1e-6 ||
    contrast_row$n[[1]] != primary_summary$n[[1]] || sum(primary_risks$n) != primary_summary$n[[1]] ||
    abs(sum(primary_risks$weighted_total) - primary_summary$weighted_total[[1]]) > max(1, primary_summary$weighted_total[[1]] * 1e-8)) {
  stop("Primary risks, contrasts, and analysis-summary counts do not reconcile.", call. = FALSE)
}
transfer <- read_public_schema("transfer_exclusions.csv", c(
  "YEAR", "stage", "entering_n", "entering_weighted", "excluded_n",
  "excluded_weighted", "remaining_n", "remaining_weighted"
))
expected_stages <- c(
  "Death or unknown vital status", "Discharge after November",
  "Combined same-day, rehabilitation, and acute-transfer exclusions"
)
if (nrow(transfer) != 7L * 3L || any(table(transfer$YEAR) != 3L) ||
    any(vapply(split(transfer$stage, transfer$YEAR), function(stages) {
      !identical(as.character(stages), expected_stages)
    }, logical(1)))) {
  stop("Transfer exclusions must contain the three reviewed coarsened stages per year.", call. = FALSE)
}
read_public_schema("first_readmission_mortality.csv", c(
  "group", "denominator", "weighted_mortality_risk", "standard_error",
  "ci_low", "ci_high", "observed_status_denominator_n",
  "observed_status_weighted_denominator", "unknown_status_excluded_n"
))
local_release_dir <- file.path(project_dir, "docs", "data")
dir.create(local_release_dir, recursive = TRUE, showWarnings = FALSE)
existing_release_files <- list.files(local_release_dir, recursive = TRUE, full.names = TRUE,
                                     all.files = TRUE, no.. = TRUE)
existing_release_files <- existing_release_files[!dir.exists(existing_release_files)]
unexpected_release_files <- setdiff(basename(existing_release_files), public_results)
nested_release_files <- existing_release_files[dirname(existing_release_files) != local_release_dir]
if (length(unexpected_release_files) || length(nested_release_files)) {
  stop("docs/data contains files outside the public aggregate allow-list: ",
       paste(c(unexpected_release_files, nested_release_files), collapse = ", "), call. = FALSE)
}
for (name in public_results) {
  if (!file.copy(file.path(project_dir, "results", name),
                 file.path(local_release_dir, name), overwrite = TRUE)) {
    stop("Could not stage aggregate table for report links: ", name, call. = FALSE)
  }
}

forbidden <- list.files(file.path(project_dir, "results"), recursive = TRUE,
                        full.names = TRUE, all.files = TRUE, no.. = TRUE)
forbidden <- forbidden[grepl("\\.(parquet|rds|rdata|rda)$", forbidden, ignore.case = TRUE)]
if (length(forbidden)) {
  message("Record-level or serialized files exist locally; they will not be copied.")
}

quarto <- Sys.which("quarto")
if (!nzchar(quarto)) stop("Quarto is not on PATH.", call. = FALSE)
for (format in c("html", "docx")) {
  status <- system2(quarto, c("render", "quarto/index.qmd", "--to", format),
                    stdout = "", stderr = "")
  if (!identical(status, 0L)) stop("Quarto render failed for ", format, ".", call. = FALSE)
}
rendered_docx <- file.path(project_dir, "docs", "quarto", "index.docx")
rendered_html <- file.path(project_dir, "docs", "quarto", "index.html")
if (!file.exists(rendered_html)) stop("Expected HTML report was not created: ", rendered_html, call. = FALSE)
if (!file.exists(rendered_docx)) stop("Expected Word deliverable was not created: ", rendered_docx, call. = FALSE)
landing_page <- c(
  "<!doctype html>",
  "<html lang=\"en\"><head><meta charset=\"utf-8\">",
  "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
  "<meta http-equiv=\"refresh\" content=\"0; url=quarto/index.html\">",
  "<title>Heart failure readmission study</title></head><body>",
  "<p>The report is opening. If it does not open automatically, <a href=\"quarto/index.html\">read the study report</a> or <a href=\"quarto/index.docx\">download the Word version</a>.</p>",
  "</body></html>"
)
writeLines(landing_page, file.path(project_dir, "docs", "index.html"), useBytes = TRUE)
site_files <- list.files(file.path(project_dir, "docs"), recursive = TRUE,
                         full.names = TRUE, all.files = TRUE, no.. = TRUE)
site_files <- site_files[!dir.exists(site_files)]
site_relative <- substring(site_files, nchar(file.path(project_dir, "docs")) + 2L)
site_files <- site_files[gsub("\\\\", "/", site_relative) != "index.docx"]
site_relative <- site_relative[gsub("\\\\", "/", site_relative) != "index.docx"]
site_relative_slash <- gsub("\\\\", "/", site_relative)
site_files <- site_files[site_relative_slash != "index.docx"]
site_relative <- site_relative[site_relative_slash != "index.docx"]
site_relative_slash <- site_relative_slash[site_relative_slash != "index.docx"]
site_relative_slash <- gsub("\\\\", "/", site_relative_slash)
private_site_files <- site_relative[grepl(
  "(^|/)(privateaudits?|manifests?|small_cell_count_audit|small_cell_suppression_audit|survey_psu_frame)(/|\\.|$)|\\.(parquet|rds|rdata|rda)$",
  site_relative_slash, ignore.case = TRUE
)]
if (length(private_site_files)) {
  stop("The rendered docs tree contains private audit or record-level files: ",
       paste(private_site_files, collapse = ", "), call. = FALSE)
}
release_data_files <- site_relative_slash[startsWith(site_relative_slash, "data/")]
if (!setequal(release_data_files, paste0("data/", public_results))) {
  stop("docs/data does not contain exactly the 23 allowlisted aggregate CSVs.", call. = FALSE)
}
message("Rendered HTML site and Word report under docs/.")
if (!publish && !sync_only) {
  message("Build only. Review docs/index.html, docs/quarto/index.html, and docs/quarto/index.docx. Pass --sync to stage a local site-checkout update; use --publish only after final review.")
  quit(save = "no", status = 0)
}

site_repo <- Sys.getenv("NRD_HF_SITE_REPO", unset = "")
if (!nzchar(site_repo)) {
  site_repo <- file.path(project_dir, "..", "..", "..", "Quarto", "NRD-HF-Fragmentation")
}
site_repo <- normalizePath(site_repo, winslash = "/", mustWork = TRUE)
git <- Sys.which("git")
if (!nzchar(git)) stop("Git is not on PATH.", call. = FALSE)

git_output <- function(args, must_succeed = TRUE) {
  out <- system2(git, c("-C", shQuote(site_repo), args), stdout = TRUE, stderr = TRUE)
  status <- attr(out, "status")
  if (is.null(status)) status <- 0L
  if (must_succeed && status != 0L) stop(paste(out, collapse = "\n"), call. = FALSE)
  list(output = out, status = status)
}
if (!file.exists(file.path(site_repo, ".git"))) stop("NRD_HF_SITE_REPO must be a Git checkout.", call. = FALSE)
origin <- git_output(c("remote", "get-url", "origin"))$output
if (!grepl("github\\.com[:/]MSaadAsif/NRD-HF-Fragmentation(\\.git)?$", origin[[1]], ignore.case = TRUE)) {
  stop("The site repository origin must be github.com/MSaadAsif/NRD-HF-Fragmentation.", call. = FALSE)
}
dirty <- git_output(c("status", "--porcelain"))$output
if (length(dirty)) {
  dirty_paths <- substring(dirty, 4L)
  allowed_dirty <- startsWith(dirty_paths, "docs/") |
    dirty_paths %in% c("README.md", public_source_files) |
    dirty_paths %in% paste0("results/", public_results)
  if (!publish || any(!allowed_dirty)) {
    stop("The site repository must be clean (or contain only allowlisted report-sync changes for --publish).", call. = FALSE)
  }
}

tracked <- git_output(c("ls-files"))$output
tracked_source_allowlist <- c("README.md", public_source_files, paste0("results/", public_results))
unapproved_tracked <- tracked[!startsWith(tracked, "docs/") & !tracked %in% tracked_source_allowlist]
if (length(unapproved_tracked)) {
  stop("Unexpected files are already tracked in the site repository: ",
       paste(unapproved_tracked, collapse = ", "), call. = FALSE)
}
tracked_docs <- tracked[startsWith(tracked, "docs/")]
tracked_doc_data <- tracked_docs[startsWith(tracked_docs, "docs/data/")]
unapproved_doc_data <- setdiff(tracked_doc_data, paste0("docs/data/", public_results))
tracked_doc_assets <- setdiff(tracked_docs, tracked_doc_data)
allowed_doc_asset <- grepl(
  "\\.(html?|css|js|png|jpe?g|svg|webp|gif|woff2?|ttf|xml|json|docx)$",
  tracked_doc_assets, ignore.case = TRUE
) | tracked_doc_assets %in% c("docs/.nojekyll", "docs/robots.txt")
if (length(unapproved_doc_data) || any(!allowed_doc_asset)) {
  stop("The site repository docs tree contains files outside the rendered-site allow-list: ",
       paste(c(unapproved_doc_data, tracked_doc_assets[!allowed_doc_asset]), collapse = ", "),
       call. = FALSE)
}

site_results_dir <- file.path(site_repo, "results")
if (dir.exists(site_results_dir)) {
  existing_result_files <- list.files(site_results_dir, recursive = TRUE,
    full.names = TRUE, all.files = TRUE, no.. = TRUE)
  existing_result_files <- existing_result_files[!dir.exists(existing_result_files)]
  existing_result_relative <- substring(existing_result_files,
    nchar(site_results_dir) + 2L)
  allowed_result_files <- paste0("results/", public_results)
  existing_result_relative <- paste0("results/", gsub("\\\\", "/", existing_result_relative))
  unexpected_result_files <- setdiff(existing_result_relative, allowed_result_files)
  if (length(unexpected_result_files)) {
    stop("The site repository results directory contains files outside the public aggregate allow-list: ",
      paste(unexpected_result_files, collapse = ", "), call. = FALSE)
  }
}

# The public repository carries the report source and only the same aggregate
# CSVs that are linked from the rendered site. Never copy analysis scripts,
# row-level cohorts, manifests, survey frames, or private audit files.
for (name in public_source_files) {
  source_path <- file.path(project_dir, name)
  if (!file.exists(source_path)) stop("Public report source is missing: ", name, call. = FALSE)
  target_path <- file.path(site_repo, name)
  dir.create(dirname(target_path), recursive = TRUE, showWarnings = FALSE)
  if (!file.copy(source_path, target_path, overwrite = TRUE)) {
    stop("Could not stage public report source: ", name, call. = FALSE)
  }
}
dir.create(site_results_dir, recursive = TRUE, showWarnings = FALSE)
for (name in public_results) {
  if (!file.copy(file.path(project_dir, "results", name),
                 file.path(site_results_dir, name), overwrite = TRUE)) {
    stop("Could not stage public aggregate result: ", name, call. = FALSE)
  }
}

site_files <- list.files(file.path(project_dir, "docs"), recursive = TRUE,
                         full.names = TRUE, all.files = TRUE, no.. = TRUE)
site_files <- site_files[!dir.exists(site_files)]
site_relative <- substring(site_files, nchar(file.path(project_dir, "docs")) + 2L)
allowed_site_file <- grepl("\\.(html?|css|js|png|jpe?g|svg|webp|gif|woff2?|ttf|xml|json|docx)$",
                           site_relative, ignore.case = TRUE)
allowed_site_file <- allowed_site_file | site_relative %in% c("robots.txt", ".nojekyll")
allowed_site_file <- allowed_site_file |
  site_relative %in% file.path("data", public_results)
if (any(!allowed_site_file)) {
  stop("The rendered site contains a file type that is not on the public-output allow-list: ",
       paste(site_relative[!allowed_site_file], collapse = ", "), call. = FALSE)
}
dest <- file.path(site_repo, "docs")
dir.create(dest, recursive = TRUE, showWarnings = FALSE)
repo_root <- normalizePath(site_repo, winslash = "/", mustWork = TRUE)
docs_root <- normalizePath(dest, winslash = "/", mustWork = TRUE)
if (identical(tolower(repo_root), tolower(docs_root)) ||
    !startsWith(tolower(docs_root), paste0(tolower(repo_root), "/"))) {
  stop("Resolved site docs path is not safely contained within the site repository.", call. = FALSE)
}
existing_site_files <- list.files(docs_root, recursive = TRUE, full.names = TRUE,
                                  all.files = TRUE, no.. = TRUE)
existing_site_files <- existing_site_files[!dir.exists(existing_site_files)]
existing_relative <- gsub("\\\\", "/", substring(existing_site_files, nchar(docs_root) + 2L))
existing_allowed <- grepl("\\.(html?|css|js|png|jpe?g|svg|webp|gif|woff2?|ttf|xml|json|docx)$",
                          existing_relative, ignore.case = TRUE) |
  existing_relative %in% c("robots.txt", ".nojekyll") | startsWith(existing_relative, "data/")
if (any(!existing_allowed)) {
  stop("Resolved site docs tree contains files outside the rendered-site allow-list: ",
       paste(existing_relative[!existing_allowed], collapse = ", "), call. = FALSE)
}
unexpected_data <- existing_relative[startsWith(existing_relative, "data/") &
  !existing_relative %in% paste0("data/", public_results)]
if (length(unexpected_data)) {
  stop("Resolved site docs data directory contains a file outside the aggregate allow-list: ",
       paste(unexpected_data, collapse = ", "), call. = FALSE)
}
for (path in existing_site_files) {
  resolved <- normalizePath(path, winslash = "/", mustWork = TRUE)
  if (!startsWith(tolower(resolved), paste0(tolower(docs_root), "/"))) {
    stop("A resolved docs file escapes the site docs directory.", call. = FALSE)
  }
}
stale_files <- existing_site_files[!existing_relative %in% site_relative_slash]
if (length(stale_files) && any(!file.remove(stale_files))) {
  stop("Could not remove obsolete rendered files from the validated site docs tree.", call. = FALSE)
}
copied <- vapply(seq_along(site_files), function(i) {
  target <- file.path(dest, site_relative[[i]])
  dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
  file.copy(site_files[[i]], target, overwrite = TRUE, recursive = TRUE)
}, logical(1))
if (length(copied) && !all(copied)) stop("Could not copy all rendered site files.", call. = FALSE)

if (sync_only) {
  message("Synced the reviewed report assets and aggregates into the site checkout. No Git commit or push was run.")
  quit(save = "no", status = 0)
}

git_output(c("add", "--", "docs", "_quarto.yml", "quarto/index.qmd",
             "REPRODUCING.md", "README.md", "publish.R", "results"))
staged <- git_output(c("diff", "--cached", "--name-only"))$output
if (!length(staged)) {
  message("Site repository already matches the reviewed report; nothing to publish.")
  quit(save = "no", status = 0)
}
git_output(c("commit", "-m", shQuote("Publish reviewed HF readmission report")))
git_output(c("push", "origin", "HEAD"))
message("Published reviewed report to https://msaadasif.github.io/NRD-HF-Fragmentation/.")
