# Data sources and access requirements

Detailed reference for the seven series collected by `R/01_collect_data.R`.
Summary version in [`../README.md`](../README.md).

Each entry records what the source is, how it is accessed, what is required to
access it, and what the resulting raw file looks like.

---

## 1. Yahoo Finance — gold in AUD

| | |
|---|---|
| **Series** | `GOLD.AX` — Global X Physical Gold ETF, ASX listed, priced in AUD |
| **Endpoint** | `https://query1.finance.yahoo.com/v8/finance/chart/GOLD.AX` |
| **Parameters** | `range=max`, `interval=1d` |
| **Access requirement** | None |
| **Raw file** | `data/raw/GOLD.AX.csv` — Date, Open, High, Low, Close, Volume |

**Notes.** This is an unofficial API with no documentation and no service
agreement; Yahoo may change or withdraw it at any time. A browser `User-Agent`
header is required or the request is refused.

**Important behaviour.** With `range=max` the API **ignores `interval`** and
returns **monthly** bars. The request asks for daily data and receives monthly
data, silently. Use a bounded range such as `range=10y` if daily observations
are needed.

Early ASX years contain `0` in High, Low and Volume; only the price column is
used, so these do not enter the analysis.

**Two corrections are applied to this series.** Both were found by cross-checking
it against the independent CRSP gold measure, and both would otherwise have
corrupted the results silently.

*Timestamps are exchange-local, not UTC.* Yahoo timestamps mark the start of each
bar in the exchange's own timezone. A monthly bar opening 1 January in Sydney is
2007-12-31 13:00 UTC, so reading the date in UTC labels every ASX bar with the
**previous month**, shifting the entire series one month against every other
source. `01_collect_data.R` reads the date back using
`meta$exchangeTimezoneName`.

*The 10-for-1 split is not adjusted by Yahoo.* `AdjClose` is byte-identical to
`Close` for this ticker, and Yahoo's own split record gives the wrong date
(2022-06-08, where the price series shows no break). The real discontinuity is
December 2010 to January 2011, where the quoted price falls from 134.67 to 13.07
- a fictional -90% month. `02_clean_merge.R` divides pre-2011 prices by 10
explicitly and warns if any monthly move above 50% survives.

Effect of the two fixes, measured against the CRSP gold series over 203
overlapping months:

| State | Correlation with CRSP gold |
|---|---|
| Neither fix | -0.001 |
| Timezone fixed only | 0.630 |
| Both fixed | **0.948** |

---

## 2. Yahoo Finance — bitcoin in AUD

| | |
|---|---|
| **Series** | `BTC-AUD` — bitcoin priced in Australian dollars |
| **Endpoint** | `https://query1.finance.yahoo.com/v8/finance/chart/BTC-AUD` |
| **Access requirement** | None |
| **Raw file** | `data/raw/BTC-AUD.csv` — Date, Open, High, Low, Close, Volume |

**Notes.** Same monthly-bar behaviour as `GOLD.AX`.

Bitcoin trades continuously, so the bar for the month in progress updates
constantly. Yahoo also returns **two rows** for the current month: the monthly
bar and a partial row dated today. `02_clean_merge.R` collapses to the last
observation per month and then drops the current month entirely, otherwise the
join key would not be unique and two runs on different days would differ.

This series begins October 2014 and is the binding constraint on the start of
the common sample.

---

## 3. Reserve Bank of Australia — AUD/USD

| | |
|---|---|
| **Series** | `FXRUSD` from statistical table F11, Exchange Rates |
| **Endpoints** | Historical to Dec 2009: `https://www.rba.gov.au/statistics/tables/xls-hist/f11hist-1969-2009.xls` <br> Current from Jan 2010: `https://www.rba.gov.au/statistics/tables/csv/f11-data.csv` |
| **Access requirement** | None — fully open |
| **Raw file** | `data/raw/AUD_USD_RBA.csv` — date, audusd (from July 1969) |

**Notes.** The RBA splits table F11 across two files, so both must be
downloaded and joined. The two are verified to meet without a duplicated or
missing month.

**Parsing trap.** Both files carry 10 metadata rows before the header. In that
header the first column is labelled `Series ID`, but the column actually holds
the **observation dates**. The code therefore reads dates from a column named
`Series ID`, which looks wrong but is correct. A change to the RBA file layout
would break this silently, since `skip = 10` is positional.

Observations are dated the **last day** of each month, unlike the Yahoo series.

---

## 4. AustralianSuper — cumulative daily rates

| | |
|---|---|
| **Series** | Cumulative daily returns for 10 investment options, indexed to 1 July 2008 |
| **Endpoint** | `https://www.australiansuper.com/api/graphs/dailyrates/download/` |
| **Parameters** | `start`, `end`, `cumulative=True`, `superType=super`, `truncateDecimalPlaces=True`, `outputFilename` |
| **Access requirement** | **Chrome or Edge must be installed** |
| **Raw file** | `data/raw/AustralianSuper_cumulative_daily_rates.csv` — Rate Date + 10 option columns |

**The access barrier.** The site is behind an Akamai bot filter that returns
HTTP 403 to every non-browser client. Confirmed failures:

| Client | Result |
|---|---|
| `httr2` with full browser headers | 403 |
| `download.file(method = "wininet")` | 403 |
| `download.file(method = "libcurl")` | 403 |
| `curl` with browser `User-Agent`, on both `www` and bare hostnames | 403 |
| The fund's own homepage via `curl` | 403 |

The filter fingerprints the TLS client, not the HTTP headers, so no combination
of headers makes a plain HTTP client work. Only a real browser succeeds.

**The workaround.** `browser_download()` launches headless Chrome or Edge with
a throwaway profile, loads an ordinary page first so the filter's JavaScript
challenge runs and deposits its cookies, then requests the file URL reusing that
profile. The stock headless user agent identifies itself as `HeadlessChrome`
and is blocked, so it is overridden.

Browser paths are currently searched in Windows locations. Set
`CHROMOTE_CHROME` to the browser executable on other platforms.

**Data notes.** Values are cumulative **percentages**, so `270.5` means
+270.5%. `02_clean_merge.R` converts these to index levels. The file includes
**weekend rows**, unlike every other daily series here. One option
(`Indexed Diversified`) is blank until 2011-07-02, and 2015-04-18 is a one-day
gap affecting seven options; neither is among the three options used.

---

## 5. Australian Retirement Trust — unit prices

| | |
|---|---|
| **Series** | Daily entry and exit unit prices for 3 asset-class options |
| **Base URL** | `https://api.art.com.au/integration/publicweb/v1` |
| **Endpoints** | `investment/product/funds?productCodes=SOL` <br> `investment/unit-price/product/SOL/effective-dates` <br> `investment/unit-price/history/data?fundCodes=&fromDate=&toDate=` |
| **Access requirement** | None, but see below |
| **Raw file** | `data/raw/AustralianRetirementTrust_unit_prices.csv` — Date, Group, FundCode, FundName, EntryPrice, ExitPrice |

**How this was found.** The public page
`australianretirementtrust.com.au/investments/performance/unit-prices` has no
download link and builds its table in JavaScript, so there is nothing to scrape
from the HTML. The API base URL, subscription key and endpoint paths were found
by reading the site's own JavaScript bundle.

**Required headers.** All three are mandatory:

```
x-art-subscription-key       cd5f1fdb33994fe7ac89d1367d5edba0
x-art-initiating-application PublicWeb
x-art-correlation-id         <any GUID>
```

The correlation id is undocumented and easy to miss: without it every request
returns HTTP 400, even with a valid subscription key. The subscription key is
published in the fund's own client-side JavaScript, but it could be rotated at
any time, which would break this step.

**Fund codes used.** Product `SOL` (Accumulation & TTR). The three Asset class
options collected:

| Code | Option |
|---|---|
| `44` | Australian Shares Index |
| `32` | International Shares Unhedged Index |
| `23` | Bonds Index |

Codes rather than names are used because the API accepts codes, and a name
change would silently break a name-based filter. `download_art_unit_prices()`
fetches the full fund list first and fails with an explicit message if a
requested code does not exist. Pass `fund_codes = NULL` to collect all 18
options; the other product code is `R00003` (Income account).

**Batching.** Fund codes cannot be batched — comma and pipe separators both
return 400 — so the function makes one request per option. This is why step 01
takes around 45 seconds for this source alone.

**Data notes.** Prices of exactly `0.000000` are placeholder rows for dates
before an option began trading; 944 of the 25,904 rows. `02_clean_merge.R`
filters them out, which sets each option's true inception date. The three
options start on different dates (Australian Shares Index only from
2005-12-30), so the panel is unbalanced.

---

## 6. WRDS / CRSP — gold in USD

| | |
|---|---|
| **Series** | SPDR Gold Trust (GLD), permno 90448, CUSIP 78463V10 |
| **Table** | `crsp.dsf` (CRSP daily stock file) |
| **Host** | `wrds-pgdata.wharton.upenn.edu:9737`, database `wrds`, `sslmode=require` |
| **Access requirement** | **Institutional WRDS account with a CRSP subscription** |
| **Raw file** | `data/raw/GOLD_USD_GLD.csv` — Date, Permno, Prc |

**Authentication.** Uses the standard WRDS `pgpass` file
(`%APPDATA%\postgresql\pgpass.conf` on Windows, `~/.pgpass` elsewhere), so no
password appears in any script or in this repository. Set the username with:

```r
Sys.setenv(WRDS_USER = "your_wrds_username")
```

**Identifier choice.** The query filters on `permno == 90448` rather than
CUSIP. Both resolve to the same security, but CUSIPs are reassigned when a
company reorganises, while permno is CRSP's permanent identifier. The company
name in CRSP changes from `STREETTRACKS GOLD TRUST` to `SPDR GOLD TRUST` across
the sample; the permno does not.

**CRSP sign convention.** `prc` is stored **negative** when a day closed with
no trade and the figure is a bid/ask midpoint rather than a traded price. The
raw file preserves the sign; `02_clean_merge.R` takes the magnitude. This
particular series contains no negative or missing prices, but the convention
still applies.

**Checked for splits.** CRSP's `prc` is also unadjusted, so this series was
checked for the problem found in GOLD.AX: `cfacpr` is constant at 1 across all
5,063 observations and no daily move exceeds 15%. GLD has never split, so no
adjustment is needed here.

**Conversion to AUD.** The proposal's primary gold measure is this series
converted to Australian dollars. `AUDUSD` is US dollars per Australian dollar,
so the AUD price is the USD price **divided** by that rate. Both inputs are
month-end observations, so no timing mismatch is introduced.

**Two limitations that matter for the analysis.**

1. **Coverage ends 2024-12-31**, the end of the licensed data, while every
   other series runs to 2026. This sets the end of the common sample.
2. **GLD is an ETF, not spot gold.** CRSP covers listed securities only, so
   there is no spot bullion series in it. GLD tracks the USD gold price closely
   but drifts below it over time, because the trust sells gold to cover roughly
   0.40% a year in expenses. If the research question requires spot gold, LBMA
   or a commodities database is the appropriate source.

---

## 7. Reserve Bank of Australia — cash rate (risk-free rate)

| | |
|---|---|
| **Series** | `FIRMMCRT` — Cash Rate Target, monthly average, from table F1.1 |
| **Endpoint** | `https://www.rba.gov.au/statistics/tables/csv/f1.1-data.csv` |
| **Access requirement** | None — fully open |
| **Raw file** | `data/raw/RBA_cash_rate.csv` — date, cash_rate (from August 1990) |

**Notes.** This is the risk-free rate the proposal specifies. Every statistic in
the analysis is computed on returns in excess of it.

**Same trap, different date format.** Like table F11, this file carries 10
metadata rows before the header, and its first column is labelled `Series ID`
while actually holding the dates. But the dates here are `30/06/1969`
(`%d/%m/%Y`), not `29-Jan-2010` (`%d-%b-%Y`) as in F11. The two RBA readers
therefore need different date formats, which is easy to overlook when copying
one parser to the other.

**De-annualisation.** The rate is quoted as an annual percentage. It is
converted to a monthly rate geometrically, as `(1 + r/100)^(1/12) - 1`, so that
twelve monthly risk-free returns compound back to the quoted annual figure.
Dividing by 12 instead would overstate the risk-free rate slightly and bias
every Sharpe ratio downward.

Coverage from August 1990 comfortably spans the study period, which begins in
August 2008.

---

## Frequency and calendar summary

The single most important thing to know before joining these series: **they do
not share a calendar.**

| Series | Frequency | Dating convention |
|---|---|---|
| GOLD.AX, BTC-AUD | Monthly | Varies; collapsed to month-end in cleaning |
| AUD/USD (RBA) | Monthly | Last day of month |
| AustralianSuper | Daily | **Includes weekends** |
| ART unit prices | Daily | Trading days only |
| GLD (CRSP) | Daily | US trading days only |
| RBA cash rate (F1.1) | Monthly | Last day of month |

Joining on a raw date column matches almost nothing. `02_clean_merge.R`
therefore keys everything on year-month (`%Y-%m`), taking the last observation
in each month for the daily series.
