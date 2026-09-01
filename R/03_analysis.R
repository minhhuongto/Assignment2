# Descriptive statistics for the monthly panel, on total returns.
#
# Total rather than excess returns, because the spanning tests use total
# returns: in Huberman-Kandel the restrictions alpha = 0 and delta = 1 - b'i = 0
# are tested on raw returns, delta standing in for the absent risk-free asset.
# The cash rate enters only the Sharpe column below.

library(dplyr)
library(zoo)
library(here)

in_dir <- here("data", "processed")

rets <- read.csv(file.path(in_dir, "monthly_returns.csv"), stringsAsFactors = FALSE)
levels_panel <- read.csv(file.path(in_dir, "monthly_levels.csv"),
                         stringsAsFactors = FALSE)

series_labels <- c(
  as_aus_shares   = "AustralianSuper: Australian shares",
  as_intl_shares  = "AustralianSuper: International shares",
  as_fixed_income = "AustralianSuper: Fixed income",
  art_aus_shares  = "ART: Australian shares",
  art_intl_shares = "ART: International shares",
  art_bonds       = "ART: Fixed income",
  gold_crsp_aud   = "Gold, CRSP ETF (AUD)",
  gold_asx_aud    = "Gold, ASX ETF (AUD)",
  btc_aud         = "Bitcoin (AUD)"
)

benchmark_cols <- c("as_aus_shares", "as_intl_shares", "as_fixed_income",
                    "art_aus_shares", "art_intl_shares", "art_bonds")
gold_primary   <- "gold_crsp_aud"
gold_alt       <- "gold_asx_aud"
test_cols      <- c(gold_primary, gold_alt, "btc_aud")
all_cols       <- c(benchmark_cols, test_cols)

cat("Running descriptive analysis (total returns)...\n")

# Sample windows are read off the data so a change in coverage is picked up.
first_month <- function(v) { m <- rets$Month[!is.na(rets[[v]])]; min(m) }
last_month  <- function(v) { m <- rets$Month[!is.na(rets[[v]])]; max(m) }

full_start <- max(sapply(c(benchmark_cols, gold_primary), first_month))
full_end   <- min(sapply(c(benchmark_cols, gold_primary), last_month))

matched_start <- max(full_start, first_month("btc_aud"))
matched_end   <- min(full_end,   last_month("btc_aud"))

in_window <- function(df, from, to) df[df$Month >= from & df$Month <= to, ]

sample_full    <- in_window(rets, full_start, full_end)
sample_matched <- in_window(rets, matched_start, matched_end)

cat("  full sample   : ", full_start, " to ", full_end,
    " (", nrow(sample_full), " months)\n", sep = "")
cat("  matched sample: ", matched_start, " to ", matched_end,
    " (", nrow(sample_matched), " months)\n", sep = "")

samples <- data.frame(
  sample = c("Full", "Matched"),
  description = c(
    "Benchmark options and gold; Bitcoin not yet available",
    "Benchmark options, gold and Bitcoin over identical months"),
  start = c(full_start, matched_start),
  end   = c(full_end, matched_end),
  months = c(nrow(sample_full), nrow(sample_matched)),
  stringsAsFactors = FALSE
)

write.csv(samples, file.path(in_dir, "sample_windows.csv"), row.names = FALSE)

describe <- function(r, rf) {
  keep <- !is.na(r)
  r    <- r[keep]
  rf   <- rf[keep]
  n    <- length(r)
  if (n < 3) return(NULL)

  m    <- mean(r)
  s    <- stats::sd(r)
  dev  <- r - m
  m2   <- mean(dev^2)
  skew <- mean(dev^3) / m2^1.5
  kurt <- mean(dev^4) / m2^2 - 3
  jb   <- n / 6 * (skew^2 + kurt^2 / 4)

  # AR(1) matters here because the tests use Newey-West standard errors.
  ar1 <- if (n > 2) stats::cor(r[-n], r[-1]) else NA_real_

  # The only use of the cash rate: a mean-to-SD ratio on raw returns would
  # not be a Sharpe ratio.
  ex   <- r - rf
  s_ex <- stats::sd(ex)

  data.frame(
    n_months     = n,
    mean_pc      = 100 * m,
    median_pc    = 100 * stats::median(r),
    sd_pc        = 100 * s,
    min_pc       = 100 * min(r),
    max_pc       = 100 * max(r),
    skewness     = skew,
    exc_kurtosis = kurt,
    jb_stat      = jb,
    jb_pvalue    = stats::pchisq(jb, df = 2, lower.tail = FALSE),
    ar1          = ar1,
    ann_mean_pc  = 100 * ((1 + m)^12 - 1),
    ann_sd_pc    = 100 * s * sqrt(12),
    sharpe       = if (s_ex > 0) (mean(ex) * 12) / (s_ex * sqrt(12)) else NA_real_,
    stringsAsFactors = FALSE
  )
}

describe_sample <- function(df, cols, sample_name) {
  out <- lapply(cols, function(v) {
    st <- describe(df[[v]], df$rf)
    if (is.null(st)) return(NULL)
    cbind(data.frame(sample = sample_name, series = v,
                     label = series_labels[[v]], stringsAsFactors = FALSE), st)
  })
  do.call(rbind, out)
}

# Bitcoin cannot populate the full window, so full-sample figures for it would
# just be the matched-sample ones under a longer label.
full_cols <- c(benchmark_cols, gold_primary, gold_alt)

desc_stats <- rbind(
  describe_sample(sample_full,    full_cols, "Full"),
  describe_sample(sample_matched, all_cols,  "Matched")
)
row.names(desc_stats) <- NULL

write.csv(desc_stats, file.path(in_dir, "descriptive_statistics.csv"),
          row.names = FALSE)

cor_table <- function(df, cols, sample_name) {
  cm <- stats::cor(df[cols], use = "pairwise.complete.obs")
  data.frame(sample = sample_name, series = rownames(cm), cm,
             check.names = FALSE, stringsAsFactors = FALSE)
}

# Two files, not one: the full-sample matrix has no Bitcoin row or column.
write.csv(cor_table(sample_full, full_cols, "Full"),
          file.path(in_dir, "correlation_matrix_full.csv"), row.names = FALSE)
write.csv(cor_table(sample_matched, all_cols, "Matched"),
          file.path(in_dir, "correlation_matrix_matched.csv"), row.names = FALSE)

pairs <- expand.grid(test = test_cols, benchmark = benchmark_cols,
                     stringsAsFactors = FALSE)

test_vs_benchmark <- do.call(rbind, lapply(seq_len(nrow(pairs)), function(i) {
  tv <- pairs$test[i]
  bv <- pairs$benchmark[i]

  cor_full <- if (tv == "btc_aud") NA_real_ else
    stats::cor(sample_full[[tv]], sample_full[[bv]], use = "pairwise.complete.obs")

  data.frame(
    test_asset     = series_labels[[tv]],
    benchmark      = series_labels[[bv]],
    fund           = ifelse(startsWith(bv, "as_"), "AustralianSuper", "ART"),
    cor_full       = cor_full,
    cor_matched    = stats::cor(sample_matched[[tv]], sample_matched[[bv]],
                                use = "pairwise.complete.obs"),
    stringsAsFactors = FALSE
  )
}))

write.csv(test_vs_benchmark, file.path(in_dir, "test_vs_benchmark_correlation.csv"),
          row.names = FALSE)

# A static correlation will not show a diversification benefit that disappears
# when equities fall, which is when it would be needed.
window <- 24

roll_pairs <- expand.grid(
  test = c(gold_primary, gold_alt, "btc_aud"),
  benchmark = c("as_aus_shares", "art_aus_shares"),
  stringsAsFactors = FALSE
)

roll_list <- lapply(seq_len(nrow(roll_pairs)), function(i) {
  tv <- roll_pairs$test[i]
  bv <- roll_pairs$benchmark[i]
  d  <- rets[c("Month", bv, tv)]
  d  <- d[stats::complete.cases(d), ]
  if (nrow(d) < window) return(NULL)

  rc <- zoo::rollapply(
    d[c(bv, tv)], width = window,
    FUN = function(w) stats::cor(w[, 1], w[, 2]),
    by.column = FALSE, fill = NA, align = "right"
  )
  data.frame(
    Month       = d$Month,
    test_asset  = series_labels[[tv]],
    fund        = ifelse(startsWith(bv, "as_"), "AustralianSuper", "ART"),
    correlation = as.numeric(rc),
    stringsAsFactors = FALSE
  )
})

rolling_cor <- do.call(rbind, roll_list)
rolling_cor <- rolling_cor[!is.na(rolling_cor$correlation), ]

write.csv(rolling_cor, file.path(in_dir, "rolling_correlation.csv"),
          row.names = FALSE)

cum_list <- lapply(all_cols, function(v) {
  r <- sample_matched[[v]]
  keep <- !is.na(r)
  if (!any(keep)) return(NULL)
  data.frame(Month = sample_matched$Month[keep],
             series = v, label = series_labels[[v]],
             index = 100 * cumprod(1 + r[keep]),
             stringsAsFactors = FALSE)
})

cumulative <- do.call(rbind, cum_list)

write.csv(cumulative, file.path(in_dir, "cumulative_index.csv"), row.names = FALSE)

# The two gold proxies are built from independent sources, so a low correlation
# here means something in the collection or conversion is wrong.
both_gold <- rets[stats::complete.cases(rets[c(gold_primary, gold_alt)]), ]

gold_check <- data.frame(
  item = c("overlap_months", "overlap_start", "overlap_end",
           "correlation", "mean_difference_pc", "sd_difference_pc"),
  value = c(
    nrow(both_gold),
    min(both_gold$Month),
    max(both_gold$Month),
    round(stats::cor(both_gold[[gold_primary]], both_gold[[gold_alt]]), 4),
    round(100 * mean(both_gold[[gold_primary]] - both_gold[[gold_alt]]), 4),
    round(100 * stats::sd(both_gold[[gold_primary]] - both_gold[[gold_alt]]), 4)
  ),
  stringsAsFactors = FALSE
)

write.csv(gold_check, file.path(in_dir, "gold_measure_comparison.csv"),
          row.names = FALSE)

cat("  gold proxies correlate ", gold_check$value[4],
    " over ", gold_check$value[1], " overlapping months\n", sep = "")
cat("Analysis results written to ", in_dir, "\n\n", sep = "")
