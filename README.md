# Hospital switching and subsequent admission after heart failure

This retrospective cohort study uses the 2016–2022 HCUP Nationwide Readmissions Database (NRD). It asks whether the first all-cause readmission after an eligible heart-failure index admission occurs at the same hospital or a different hospital, and whether hospital destination is associated with another inpatient admission within 30 days after discharge from that first readmission.

The analytic population is survivor-conditional: adults with an eligible HF index admission, a first all-cause readmission within 30 days, and a recorded live discharge from that readmission. HF diagnosis at the first readmission is not an exposure-cohort requirement. The adjusted estimates describe an association among these selected survivors; they do not estimate a causal or preventable effect of switching.

## Certified primary result

The certified primary analysis used 502,236 complete cases (394,183 same-hospital and 108,053 different-hospital first readmissions). Adjusted 30-day risks were 31.44% (95% CI, 31.26%–31.61%) and 32.49% (95% CI, 32.18%–32.80%), respectively. The adjusted risk difference was 1.06 percentage points (95% CI, 0.71–1.40); the adjusted risk ratio was 1.034 (95% CI, 1.023–1.045). These are survey-standardized associations, not evidence of clinical importance based on statistical significance alone.

Analysis run `20261024T035323+0500` used cohort run `20261023T191357+0500`. Its 23 aggregate outputs passed hash, schema, interval, denominator, convergence/fitted-df, coefficient-suppression, protected-count, and cross-row release checks. The formal independent closure is saved in [final-analysis-closure-max-20261024-r3.md](reviews/final-analysis-closure-max-20261024-r3.md). The original provisional manifest did not record fit-time package versions. The recovered checkpoint and audit-only resumer signatures matched, with no evidence of drift, but this does not independently attest the package versions loaded by the original fit process.

## Reproduce the report

From this project directory, the strict private build verifies the certified manifests and current source signatures before rendering:

```powershell
& "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" publish.R
```

The separate public Quarto checkout, `Quarto/NRD-HF-Fragmentation`, can render only the 23 released aggregate CSVs:

```powershell
& "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" publish.R --aggregate-only
```

The aggregate-only mode does not need private manifests and does not refit the analysis. The 23 CSV files are the public contract. Both publisher modes validate the reviewed table schemas and scan public text cells for internal design identifiers before rendering. Keep raw NRD files, linked cohorts, survey frames, run manifests, private audits, and credentials out of Git and the public site. See [REPRODUCING.md](REPRODUCING.md) for the full authorized rebuild and release boundaries.

## Interpretation limits and author declarations

Hospital identifiers describe hospital sites. They do not establish provider continuity, shared records, a hospital network, transfer appropriateness, or quality. Conditioning on readmission and survival can induce selection bias; residual confounding and informative missingness remain possible. NRD follow-up does not cross state or calendar-year boundaries and does not observe out-of-hospital death.

Before submission, authors must confirm the institutional review board determination, applicable HCUP data-use language, affiliations and contributions, funding and funder role, acknowledgments, and conflicts of interest. These author facts are not inferred from the analysis files.
