# Reproduce the report and analysis

The canonical analysis source is this project. `quarto/index.qmd` is the single manuscript source for HTML and DOCX. `Quarto/NRD-HF-Fragmentation` is the separate public-site checkout. It contains only report assets and disclosure-reviewed aggregate tables; it does not contain the analysis scripts, licensed NRD files, linked records, private audit evidence, or manifests.

## Render from already released aggregate tables

The public checkout includes the exact aggregate CSV allowlist under `results/` for rendering and under `docs/data/` for download links. It does not need private manifests. From the root of a clean public checkout, run:

```powershell
Rscript publish.R --aggregate-only
```

This mode validates the exact aggregate file and schema allowlists, checks every public text cell for internal survey-design/hospital identifiers, checks the primary model contract and count fields, refreshes `docs/data/`, and renders HTML and DOCX from `quarto/index.qmd`. It assumes the published aggregates already passed the private manifest, suppression, and cross-row release gates before entering the public checkout. It does not run cohort construction, refit models, commit, push, or deploy.

The build requires Quarto and R packages `dplyr`, `readr`, `knitr`, `ggplot2`, `scales`, `tidyr`, and `flextable`. Check `docs/index.html`, `docs/quarto/index.html`, and `docs/quarto/index.docx` after rendering.

## Rebuild the analysis with authorized NRD data

The private rebuild requires authorized `NRD_2016.parquet` through `NRD_2022.parquet` files in a separate data directory and the packages used by the cohort and analysis scripts. Those scripts are kept in the private analysis source and are not included in this public checkout. From the root of that private project, set `NRD_DATA_DIR` to the licensed input directory, then run:

```powershell
$env:Path = "C:\Program Files\R\R-4.6.1\bin;C:\Program Files\Quarto\bin;" + $env:Path
$env:NRD_DATA_DIR = "C:\path\to\authorized\nrd_data"
& "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" scripts/01_cohort.R
& "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" scripts/02_analysis.R
& "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" publish.R
```

The cohort build writes local linked Parquet files, survey-frame metadata, and a cohort manifest. The analysis writes aggregate tables and an analysis manifest after the small-cell and cross-row release checks. The private publisher checks the current script hashes, both manifests, output checksums, audit flags and per-table suppression evidence before rendering. It also scans all text values in the 23 public tables for internal design identifiers and rejects a schema-valid table with leaked diagnostic text. It requires the complete `primary_enriched` risks, contrasts, coefficients, and analysis summary; it will not substitute historical estimates for a missing primary model.

The certified current runs are cohort `20261023T191357+0500` and analysis `20261024T035323+0500`. Analysis certification covers exactly 23 output CSVs and both release-audit flags. The final independent closure confirmed current hashes/schemas, intervals, denominator reconciliation, fitted-model diagnostics, term-level coefficient suppression, and the cohort-bound protected-count recheck. The original provisional manifest did not contain fit-time R/package-version fields. The recovered checkpoint and audit-only resumer signatures matched and no package drift was observed; this confirms recovery-to-release consistency but does not independently attest the packages loaded by the original fit process. No new fit was run to address this nonblocking provenance limit.

The public analysis-summary export omits the internal empty-factor-level diagnostics because that inventory can contain design identifiers. `scripts/analysis_release.R` removes that field from the public summary and validates remaining public text; `publish.R` independently repeats an all-text-cell identifier scan at the release boundary. Both controls fail closed before report rendering.

Keep raw annual files, linked cohorts, survey PSU frames, manifests, private audits, and credentials out of Git and the public site. Each NRD year is a separate sample: identifiers are year-specific, and the analysis does not link people across years, states, or the annual follow-up boundary.

## Review and publish the public site

The default site checkout used by `publish.R --sync` and `publish.R --publish` is the sibling `Quarto/NRD-HF-Fragmentation`; set `NRD_HF_SITE_REPO` only when it is stored elsewhere. `--sync` checks that checkout is clean, verifies the source, rendered-site, and exact aggregate allowlists, and synchronizes the validated `docs/` tree without staging, committing, or pushing. Review that local diff. After final approval, `--publish` can use only those allowlisted report-sync changes; it rerenders, revalidates the release, commits, and pushes.

Do not run `publish.R --publish` until the certified analysis outputs, disclosure checks, rendered HTML, Word visual review, and parent review are complete. The build without `--publish` renders locally only.
