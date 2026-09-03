# Do Gold and Bitcoin Expand the Opportunity Set for Australian Superannuation Members?

Empirical implementation of the Assessment 1 proposal. This repository collects
the data, builds the monthly return panel, and produces the descriptive
statistics, tables and figures that the mean–variance spanning tests
(Huberman–Kandel 1987; Kan–Zhou 2012) and the out-of-sample portfolio tests
will build on.

The repository contains **code and documentation only**. No data files are
distributed. Running the pipeline recreates every dataset from its original
source and regenerates every output.

---

## Quick start

```r
# 1. Open Assignment2.Rproj in RStudio (this sets the working directory)
# 2. Create a .Renviron file in the project root with two lines
#    (see Credentials below), then restart R so they are loaded
# 3. Install dependencies, once:
source("R/install_packages.R")
# 4. Run the whole pipeline:
source("R/00_run_all.R")
```

Roughly 3–5 minutes end to end. Tables appear in `output/tables/`, figures in
`output/figures/`.

**Before running, read [Data sources and access requirements](#data-sources-and-access-requirements).**
Two of the seven series need more than an internet connection.

---

## Research design implemented here

| Role | Series |
|------|--------|
| Benchmark assets | DIY options of **AustralianSuper** and **ART**, analysed separately: Australian shares, international shares, fixed income |
| Test asset 1 | **Gold** — CRSP gold ETF in USD converted to AUD at the RBA rate (primary); ASX-listed gold ETF in AUD (alternative) |
| Test asset 2 | **Bitcoin** — BTC-AUD |
| Risk-free rate | **RBA cash rate target** (table F1.1, `FIRMMCRT`) — reported only, see below |

All statistics are computed on **monthly total returns**, which is the quantity
the spanning tests use. This follows the classic Huberman–Kandel (1987) setup:
the two restrictions α = 0 and δ = 1 − β′ι = 0 are tested on raw returns, and
the δ restriction exists precisely because no risk-free asset is assumed.

The cash rate is still collected, but it enters only the `Sharpe (vs cash)`
column of the descriptive tables, where a ratio of mean return to standard
deviation would otherwise not be a Sharpe ratio. It is retained because the
Stage 2 performance measures (Sharpe, Sortino, Omega) require it.

Two sample windows, as specified in the proposal:

| Sample | Window | Months | Contents |
|--------|--------|--------|----------|
| **Full** | 2008-08 → 2024-12 | 197 | Benchmarks and gold; Bitcoin does not yet exist |
| **Matched** | 2014-11 → 2024-12 | 122 | Benchmarks, gold and Bitcoin over identical months |

Bitcoin's start sets the beginning of the matched sample. The end of the CRSP
licence, not the data itself, sets the end of both.

---

## Repository structure

```
Assignment2/
├── Assignment2.Rproj          RStudio project; sets the working directory
├── README.md                  this file
├── .gitignore                 excludes data and credentials
│
├── R/
│   ├── 00_run_all.R           runs steps 01–04 in order
│   ├── 01_collect_data.R      original sources   -> data/raw/
│   ├── 02_clean_merge.R       data/raw/          -> data/processed/
│   ├── 03_analysis.R          panel              -> descriptive results
│   ├── 04_tables_figures.R    results            -> output/
│   └── install_packages.R     dependency installer
│
├── data/                      not tracked by git; created by the pipeline
│   ├── raw/                   sources exactly as downloaded
│   └── processed/             cleaned series, monthly panel, results
│
├── output/
│   ├── tables/                tab01–tab06 (.csv)
│   └── figures/               fig01–fig06 (.png)
│
└── docs/
    ├── data_sources.md        detailed source and access notes
    └── session_info.txt       R and package versions of the last full run
```

Raw data is never overwritten. `01_collect_data.R` writes only to `data/raw/`,
and every filtering, conversion and column decision happens in
`02_clean_merge.R`. Any cleaning choice can therefore be revisited without
downloading again.

---

## Outputs

### Tables

| File | Contents |
|------|----------|
| `tab01_data_sources.csv` | Series, source, access requirement, coverage obtained |
| `tab02_descriptives_full_sample.csv` | Descriptive statistics, full sample |
| `tab03_descriptives_matched_sample.csv` | Descriptive statistics, matched sample |
| `tab04_correlation_full_sample.csv` | Correlation matrix, full sample |
| `tab05_correlation_matched_sample.csv` | Correlation matrix, matched sample |
| `tab06_test_vs_benchmark_correlation.csv` | Each test asset against each fund's options |

Descriptive tables report N, mean, median, SD, min, max, skewness, excess
kurtosis, a Jarque–Bera p-value, AR(1), annualised mean and SD, all on total
returns, plus a Sharpe ratio computed against the cash rate. AR(1) is
included because the proposal uses Newey–West HAC standard errors, which
matter when returns are autocorrelated.

### Figures

| File | Contents |
|------|----------|
| `fig01_cumulative_growth.png` | Cumulative growth of A$100, total returns, log scale |
| `fig02_risk_return.png` | Annualised risk against total return, both samples, log–log |
| `fig03_correlation_heatmap.png` | Correlation matrix, matched sample |
| `fig04_rolling_correlation.png` | 24-month rolling correlation with each fund's Australian shares |
| `fig05_return_distributions.png` | Distribution of monthly total returns |
| `fig06_data_coverage.png` | Coverage of each series and the matched sample window |

---

## Data sources and access requirements

| # | Source | Series | Access | Requirement |
|---|--------|--------|--------|-------------|
| 1 | AustralianSuper | 3 DIY options | Internal API behind a bot filter | **Chrome or Edge must be installed** |
| 2 | Australian Retirement Trust | 3 DIY options | Undocumented internal API | `ART_SUBSCRIPTION_KEY` in `.Renviron`; see Credentials below |
| 3 | WRDS / CRSP | Gold ETF (GLD) in USD | PostgreSQL | **Licensed WRDS account required** |
| 4 | Yahoo Finance | ASX gold ETF (GOLD.AX) | Unofficial public API | None; no service agreement |
| 5 | Yahoo Finance | Bitcoin (BTC-AUD) | Unofficial public API | None |
| 6 | RBA table F11 | AUD/USD | Direct file download | None |
| 7 | RBA table F1.1 | Cash rate (`FIRMMCRT`) | Direct file download | None |

Full detail, including endpoints, required headers and the reverse-engineering
notes for sources 1 and 2, is in [`docs/data_sources.md`](docs/data_sources.md).

### AustralianSuper needs a browser

The site is behind an Akamai bot filter that returns HTTP 403 to every
non-browser client. Confirmed against `httr2` with full browser headers and
`download.file()` on both the `wininet` and `libcurl` backends. The filter
fingerprints the TLS client, so no combination of headers helps.

`01_collect_data.R` tries a direct request first, then falls back to a headless
Chrome or Edge. **Browser paths are currently Windows-specific.** On macOS or
Linux set the location first:

```r
Sys.setenv(CHROMOTE_CHROME = "/path/to/chrome")
```

### WRDS needs a licence

Requires an institutional WRDS account with a CRSP subscription.
Authentication uses the standard WRDS `pgpass` file, so **no password appears
anywhere in this repository**. The username comes from `WRDS_USER` in
`.Renviron`.

Without WRDS access the step fails cleanly and the other six series still
download. The primary gold measure is then missing, but the **ASX gold ETF
alternative still covers the whole period**, so the analysis can still run.

### Credentials

Two values are read from a `.Renviron` file in the project root. That file is
excluded by `.gitignore` and is never committed, so nothing sensitive appears in
this repository. Create it yourself with these two lines:

```
WRDS_USER=your_wrds_username
ART_SUBSCRIPTION_KEY=your_art_subscription_key
```

R reads `.Renviron` when it starts, so **restart R after creating or editing
it**.

| Variable | What it is | Where to get it |
|---|---|---|
| `WRDS_USER` | Your WRDS username. The password is *not* stored here — WRDS authenticates through the `pgpass` file it has you create (`%APPDATA%\postgresql\pgpass.conf` on Windows, `~/.pgpass` elsewhere). | Your WRDS account |
| `ART_SUBSCRIPTION_KEY` | Key for the Australian Retirement Trust public API. Not secret: it is served in the fund's own website JavaScript. It is kept out of the code so no key is committed. | Open the ART unit prices page and search the loaded JavaScript bundles for `apimSubscriptionKeyValue` |

---

## Verifying a reproduction

No data ships with the repository, so use these to confirm your run matches:

Counts below are as at 1 September 2026. Series that run to the present gain a
month with each run; the start dates and `gold_crsp_aud` do not move.

| Series | Months | First | Last |
|--------|--------|-------|------|
| `as_aus_shares`, `as_intl_shares`, `as_fixed_income` | 217 | 2008-08 | 2026-08 |
| `art_aus_shares` | 247 | 2006-02 | 2026-08 |
| `art_intl_shares`, `art_bonds` | 286 | 2002-11 | 2026-08 |
| `gold_crsp_aud` | 241 | 2004-12 | 2024-12 |
| `gold_asx_aud` | 223 | 2008-02 | 2026-08 |
| `btc_aud` | 142 | 2014-11 | 2026-08 |
| `rf` | 432 | 1990-08 | 2026-07 |

Also written each run: `data/processed/coverage_report.csv` and
`docs/session_info.txt`.

**Cross-check on the two gold measures.** They are constructed from entirely
independent sources — CRSP via WRDS, converted through the RBA exchange rate,
versus Yahoo Finance in AUD. Over their 203 overlapping months they correlate
**0.948**, with a mean monthly difference of 0.005%. If a reproduction returns
a materially lower correlation, something in the collection or conversion has
gone wrong. See `data/processed/gold_measure_comparison.csv`.

---

## Two data problems that had to be corrected

Both were found by that cross-check, and both would have corrupted the results
silently.

**Yahoo timestamps are in exchange-local time, not UTC.** A monthly GOLD.AX bar
opening on 1 January in Sydney is 13:00 UTC on 31 December. Reading the date in
UTC therefore labelled every ASX bar with the *previous month*, shifting the
whole series by one month against everything else. `01_collect_data.R` now
converts using `meta$exchangeTimezoneName`. BTC-AUD is quoted on UTC and was
never affected.

**GOLD.AX split 10 for 1, and Yahoo does not adjust for it.** `AdjClose` is
identical to `Close`, and Yahoo's own split record carries the wrong date
(2022-06-08, where the price series shows no break at all). The real
discontinuity is December 2010 to January 2011, where the quoted price falls
from 134.67 to 13.07 — a fictional −90% month. `02_clean_merge.R` applies the
adjustment explicitly and warns if any monthly move above 50% survives.

With both corrected, the two gold proxies agree at 0.948. Before the fixes they
correlated **−0.001**.

CRSP was checked for the same issue: `cfacpr` is constant at 1 for GLD and no
daily move exceeds 15%, so that series needed no adjustment.

---

## Known limitations

**The CRSP licence ends 2024-12-31**, while every other series runs to 2026-07.
This truncates both samples by about 19 months. The proposal's Appendix A1
assumes gold coverage to 2026; in practice the primary gold measure stops at
the end of 2024. The ASX gold ETF alternative does cover the full period.

**The gold series are ETFs, not spot bullion.** Both proxies hold physical gold
but drift below the metal over time through management costs. This is a
measurement choice, not an error, and should be stated in the write-up.

**Yahoo returns monthly bars, not daily.** With `range = "max"` the API ignores
the `interval` argument. This suits a monthly study, but the code documents it
so the behaviour is not mistaken for a daily series.

**The current month is excluded.** Yahoo returns two rows for the month in
progress and its value changes between runs, so `02_clean_merge.R` drops it.
This is what makes two runs on different days produce the same panel.

**Sources may break without notice.** The ART subscription key is embedded in
the fund's public JavaScript. The AustralianSuper bot filter could tighten. The
RBA parsers assume 10 metadata rows before the header.

**ART unit prices carry placeholder zeros** before an option began trading.
These are removed in cleaning, which is what sets each option's inception date.

---

## Software environment

R version 4.6.0 (2026-04-24 ucrt), Windows 11.

| Package | Version | | Package | Version |
|---------|---------|---|---------|---------|
| httr2 | 1.3.0 | | dplyr | 1.2.1 |
| jsonlite | 2.0.0 | | tidyr | 1.3.2 |
| readxl | 1.5.0 | | zoo | 1.9.0 |
| RPostgres | 1.4.10 | | ggplot2 | 4.0.3 |
| DBI | 1.3.0 | | scales | 1.4.0 |
| dbplyr | 2.6.0 | | here | 1.0.2 |

`docs/session_info.txt` is regenerated by every full run.

---

## Reproducibility practice

- All paths resolve with `here()` from the project root; no absolute paths, no
  `setwd()`.
- `01_collect_data.R` writes only to `data/raw/`; cleaning is isolated in
  `02_clean_merge.R`, so raw data is never overwritten.
- Analysis (`03`) is separate from presentation (`04`), so changing a figure
  never re-runs the analysis or triggers a download.
- Every download step is wrapped so one failing source does not stop the others.
- No credentials in any script. The WRDS username and the ART subscription key
  come from `.Renviron`, which is gitignored. The WRDS password never leaves
  the local `pgpass` file.
- Table and figure file names match the numbering used in the report.

---

## Author

Minh Huong TO (`huongtm2021@gmail.com`)
PhD Data Methods — Assessment 2
