# Clean the raw downloads and merge them into a monthly panel.
#
# The sources use four different calendars - monthly bars, month-end monthly,
# daily including weekends, and daily trading days - so nothing can be joined on
# a raw date. Everything is keyed on year-month, taking the last observation in
# the month for the daily series.

library(dplyr)
library(tidyr)
library(here)

raw_dir <- here("data", "raw")
out_dir <- here("data", "processed")
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

read_raw <- function(file) {
  path <- file.path(raw_dir, file)
  if (!file.exists(path)) return(NULL)
  read.csv(path, check.names = FALSE, stringsAsFactors = FALSE)
}

to_monthly <- function(df, date_col, value_col, new_name) {
  out <- df %>%
    mutate(Month = format(.data[[date_col]], "%Y-%m")) %>%
    group_by(Month) %>%
    slice_max(order_by = .data[[date_col]], n = 1, with_ties = FALSE) %>%
    ungroup() %>%
    select(all_of(c("Month", value_col)))
  names(out)[2] <- new_name
  out
}

cat("Cleaning raw data...\n")

# GOLD.AX split 10 for 1 and Yahoo does not adjust for it: AdjClose equals
# Close, and Yahoo's split record has the wrong date (2022-06-08, where the
# series shows no break). The real break is Dec 2010 to Jan 2011, 134.67 to
# 13.07. Corrected here.
gold_asx <- read_raw("GOLD.AX.csv") %>%
  transmute(Date = as.Date(Date), Close = as.numeric(AdjClose)) %>%
  filter(!is.na(Close))

gold_asx_splits <- data.frame(
  effective = as.Date("2011-01-01"),
  factor    = 10
)

for (i in seq_len(nrow(gold_asx_splits))) {
  pre <- gold_asx$Date < gold_asx_splits$effective[i]
  gold_asx$Close[pre] <- gold_asx$Close[pre] / gold_asx_splits$factor[i]
}

# Catch any future split that is not in the table above.
gold_asx_jump <- max(abs(diff(gold_asx$Close) / head(gold_asx$Close, -1)))
if (gold_asx_jump > 0.5) {
  warning("GOLD.AX still contains a monthly move of ",
          round(100 * gold_asx_jump, 1), "% - check for an unhandled split.")
}

write.csv(gold_asx, file.path(out_dir, "gold_asx_aud.csv"), row.names = FALSE)

btc <- read_raw("BTC-AUD.csv") %>%
  transmute(Date = as.Date(Date), Close = as.numeric(AdjClose)) %>%
  filter(!is.na(Close))
write.csv(btc, file.path(out_dir, "btc_aud.csv"), row.names = FALSE)

aud_usd <- read_raw("AUD_USD_RBA.csv") %>%
  transmute(Date = as.Date(date), AUDUSD = as.numeric(audusd)) %>%
  filter(!is.na(AUDUSD))
write.csv(aud_usd, file.path(out_dir, "aud_usd.csv"), row.names = FALSE)

cash <- read_raw("RBA_cash_rate.csv") %>%
  transmute(Date = as.Date(date), CashRate = as.numeric(cash_rate)) %>%
  filter(!is.na(CashRate))
write.csv(cash, file.path(out_dir, "cash_rate.csv"), row.names = FALSE)

as_keep <- c("Rate Date", "Australian Shares", "International Shares",
             "Diversified Fixed Interest")

aus_super_raw <- read_raw("AustralianSuper_cumulative_daily_rates.csv")
stopifnot(all(as_keep %in% names(aus_super_raw)))

aus_super <- aus_super_raw[as_keep]
names(aus_super)[1] <- "Date"
aus_super$Date <- as.Date(aus_super$Date)
aus_super <- aus_super[!is.na(aus_super$Date), ]
write.csv(aus_super, file.path(out_dir, "australiansuper.csv"), row.names = FALSE)

# Zero unit prices are placeholders for dates before an option started trading.
art <- read_raw("AustralianRetirementTrust_unit_prices.csv") %>%
  transmute(Date = as.Date(Date),
            FundName = FundName,
            EntryPrice = as.numeric(EntryPrice)) %>%
  filter(!is.na(EntryPrice), EntryPrice > 0)
write.csv(art, file.path(out_dir, "art_unit_prices.csv"), row.names = FALSE)

gold_usd_raw <- read_raw("GOLD_USD_GLD.csv")

if (is.null(gold_usd_raw)) {
  gold_usd <- NULL
  cat("  GOLD_USD_GLD.csv not found - the WRDS step was skipped.\n")
  cat("  The primary gold measure will be missing. See README.md.\n")
} else {
  gold_usd <- gold_usd_raw %>%
    transmute(Date = as.Date(Date), Close = abs(as.numeric(Prc))) %>%
    filter(!is.na(Close))
  write.csv(gold_usd, file.path(out_dir, "gold_usd.csv"), row.names = FALSE)
}

panel <- to_monthly(gold_asx, "Date", "Close", "gold_asx_aud") %>%
  full_join(to_monthly(btc, "Date", "Close", "btc_aud"), by = "Month") %>%
  full_join(to_monthly(aud_usd, "Date", "AUDUSD", "aud_usd"), by = "Month") %>%
  full_join(to_monthly(cash, "Date", "CashRate", "cash_rate"), by = "Month")

# AustralianSuper reports cumulative per cent since inception, so 270.5 means
# +270.5%. Converting to an index level lets one return formula cover every
# column in the panel.
as_monthly <- aus_super %>%
  mutate(Month = format(Date, "%Y-%m")) %>%
  group_by(Month) %>%
  slice_max(order_by = Date, n = 1, with_ties = FALSE) %>%
  ungroup()

as_monthly <- data.frame(
  Month           = as_monthly$Month,
  as_aus_shares   = 1 + as_monthly[["Australian Shares"]] / 100,
  as_intl_shares  = 1 + as_monthly[["International Shares"]] / 100,
  as_fixed_income = 1 + as_monthly[["Diversified Fixed Interest"]] / 100,
  stringsAsFactors = FALSE
)

panel <- full_join(panel, as_monthly, by = "Month")

art_monthly <- art %>%
  mutate(Month = format(Date, "%Y-%m")) %>%
  group_by(Month, FundName) %>%
  slice_max(order_by = Date, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  select(Month, FundName, EntryPrice) %>%
  pivot_wider(names_from = FundName, values_from = EntryPrice)

art_monthly <- data.frame(
  Month           = art_monthly$Month,
  art_aus_shares  = art_monthly[["Australian Shares Index"]],
  art_intl_shares = art_monthly[["International Shares Unhedged Index"]],
  art_bonds       = art_monthly[["Bonds Index"]],
  stringsAsFactors = FALSE
)

panel <- full_join(panel, art_monthly, by = "Month")

# AUDUSD is USD per AUD, so an AUD price is the USD price divided by the rate.
if (!is.null(gold_usd)) {
  panel <- full_join(panel,
                     to_monthly(gold_usd, "Date", "Close", "gold_usd"),
                     by = "Month")
  panel$gold_crsp_aud <- panel$gold_usd / panel$aud_usd
} else {
  panel$gold_usd <- NA_real_
  panel$gold_crsp_aud <- NA_real_
}

panel <- panel %>% arrange(Month)

# The month in progress is not a closed observation and changes between runs.
current_month <- format(Sys.Date(), "%Y-%m")
if (current_month %in% panel$Month) {
  panel <- panel[panel$Month != current_month, ]
  cat("  dropped ", current_month, " (month still in progress)\n", sep = "")
}

stopifnot(!any(duplicated(panel$Month)))

write.csv(panel, file.path(out_dir, "monthly_levels.csv"), row.names = FALSE)

asset_cols <- c("as_aus_shares", "as_intl_shares", "as_fixed_income",
                "art_aus_shares", "art_intl_shares", "art_bonds",
                "gold_crsp_aud", "gold_asx_aud", "btc_aud")

returns <- panel["Month"]

for (v in asset_cols) {
  x <- panel[[v]]
  r <- c(NA, x[-1] / x[-length(x)] - 1)
  # The panel is unbalanced, so a gap must not be read as a return.
  r[is.na(x) | is.na(c(NA, x[-length(x)]))] <- NA
  returns[[v]] <- r
}

# De-annualise geometrically so twelve monthly rates compound to the quoted one.
returns$rf <- (1 + panel$cash_rate / 100)^(1 / 12) - 1

write.csv(returns, file.path(out_dir, "monthly_returns.csv"), row.names = FALSE)

# Kept for reference. The spanning tests use total returns.
excess <- returns["Month"]
for (v in asset_cols) excess[[v]] <- returns[[v]] - returns$rf
excess$rf <- returns$rf

write.csv(excess, file.path(out_dir, "monthly_excess_returns.csv"), row.names = FALSE)

# No data is committed, so this is how a reproduction is checked against ours.
report_cols <- c(asset_cols, "rf")

coverage <- data.frame(
  series = report_cols,
  n_obs  = sapply(report_cols, function(v) sum(!is.na(returns[[v]]))),
  first  = sapply(report_cols, function(v) {
    m <- returns$Month[!is.na(returns[[v]])]
    if (length(m)) min(m) else NA_character_
  }),
  last   = sapply(report_cols, function(v) {
    m <- returns$Month[!is.na(returns[[v]])]
    if (length(m)) max(m) else NA_character_
  }),
  stringsAsFactors = FALSE,
  row.names = NULL
)

write.csv(coverage, file.path(out_dir, "coverage_report.csv"), row.names = FALSE)

cat("  monthly panel: ", nrow(panel), " months, ", min(panel$Month), " to ",
    max(panel$Month), "\n", sep = "")
cat("Processed data written to ", out_dir, "\n\n", sep = "")
