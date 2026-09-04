# Tables and figures. File names match the numbering used in the report.

library(ggplot2)
library(dplyr)
library(tidyr)
library(scales)
library(here)

in_dir  <- here("data", "processed")
tab_dir <- here("output", "tables")
fig_dir <- here("output", "figures")

for (d in c(tab_dir, fig_dir)) if (!dir.exists(d)) dir.create(d, recursive = TRUE)

read_processed <- function(f) {
  read.csv(file.path(in_dir, f), check.names = FALSE, stringsAsFactors = FALSE)
}

desc      <- read_processed("descriptive_statistics.csv")
corr_full <- read_processed("correlation_matrix_full.csv")
corr_mtch <- read_processed("correlation_matrix_matched.csv")
tvb       <- read_processed("test_vs_benchmark_correlation.csv")
rolling   <- read_processed("rolling_correlation.csv")
cumul     <- read_processed("cumulative_index.csv")
coverage  <- read_processed("coverage_report.csv")
windows   <- read_processed("sample_windows.csv")
rets      <- read_processed("monthly_returns.csv")

full_start    <- windows$start[windows$sample == "Full"]
full_end      <- windows$end[windows$sample == "Full"]
matched_start <- windows$start[windows$sample == "Matched"]
matched_end   <- windows$end[windows$sample == "Matched"]

# Presentation order: benchmark options first, then the test assets.
lvl <- c("AustralianSuper: Australian shares",
         "AustralianSuper: International shares",
         "AustralianSuper: Fixed income",
         "ART: Australian shares",
         "ART: International shares",
         "ART: Fixed income",
         "Gold, CRSP ETF (AUD)",
         "Gold, ASX ETF (AUD)",
         "Bitcoin (AUD)")

label_lookup <- setNames(desc$label, desc$series)
label_of <- function(v) ifelse(v %in% names(label_lookup), label_lookup[v], v)

asset_type <- function(lab) {
  ifelse(grepl("^Gold", lab), "Gold",
         ifelse(grepl("^Bitcoin", lab), "Bitcoin", "Benchmark option"))
}

as_month_date <- function(m) as.Date(paste0(m, "-01"))

theme_report <- theme_minimal(base_size = 11) +
  theme(
    panel.grid.minor = element_blank(),
    plot.title       = element_text(face = "bold", size = 12),
    plot.subtitle    = element_text(colour = "grey30", size = 9),
    plot.caption     = element_text(colour = "grey40", size = 8, hjust = 0),
    legend.position  = "bottom",
    legend.title     = element_blank()
  )

cat("Building tables and figures...\n")

# Table 1. Appendix A1 of the proposal, with the coverage actually obtained.
source_lookup <- c(
  as_aus_shares   = "AustralianSuper DIY option (fund website API)",
  as_intl_shares  = "AustralianSuper DIY option (fund website API)",
  as_fixed_income = "AustralianSuper DIY option (fund website API)",
  art_aus_shares  = "ART DIY option (fund website API)",
  art_intl_shares = "ART DIY option (fund website API)",
  art_bonds       = "ART DIY option (fund website API)",
  gold_crsp_aud   = "CRSP gold ETF in USD (WRDS), converted at the RBA AUD/USD rate",
  gold_asx_aud    = "ASX-listed gold ETF, Yahoo Finance",
  btc_aud         = "Bitcoin BTC-AUD, Yahoo Finance",
  rf              = "RBA cash rate target, table F1.1 (FIRMMCRT)"
)

access_lookup <- c(
  as_aus_shares = "Non-WRDS", as_intl_shares = "Non-WRDS", as_fixed_income = "Non-WRDS",
  art_aus_shares = "Non-WRDS", art_intl_shares = "Non-WRDS", art_bonds = "Non-WRDS",
  gold_crsp_aud = "WRDS", gold_asx_aud = "Non-WRDS", btc_aud = "Non-WRDS",
  rf = "Non-WRDS"
)

tab01 <- coverage %>%
  transmute(
    `Data series`   = ifelse(series == "rf", "Risk-free rate (monthly)", label_of(series)),
    Source          = source_lookup[series],
    Access          = access_lookup[series],
    `First month`   = first,
    `Last month`    = last,
    `Months`        = n_obs,
    Frequency       = "Monthly"
  )

write.csv(tab01, file.path(tab_dir, "tab01_data_sources.csv"), row.names = FALSE)

# Tables 2 and 3. Descriptive statistics on total returns.
format_desc <- function(d) {
  d %>%
    transmute(
      Series                = label,
      N                     = n_months,
      `Mean (%)`            = round(mean_pc, 3),
      `Median (%)`          = round(median_pc, 3),
      `SD (%)`              = round(sd_pc, 3),
      `Min (%)`             = round(min_pc, 2),
      `Max (%)`             = round(max_pc, 2),
      Skewness              = round(skewness, 3),
      `Excess kurtosis`     = round(exc_kurtosis, 3),
      `JB p-value`          = round(jb_pvalue, 4),
      `AR(1)`               = round(ar1, 3),
      `Ann. mean (%)`       = round(ann_mean_pc, 2),
      `Ann. SD (%)`         = round(ann_sd_pc, 2),
      `Sharpe (vs cash)`    = round(sharpe, 3)
    ) %>%
    arrange(factor(Series, levels = lvl))
}

tab02 <- format_desc(desc[desc$sample == "Full", ])
tab03 <- format_desc(desc[desc$sample == "Matched", ])

write.csv(tab02, file.path(tab_dir, "tab02_descriptives_full_sample.csv"), row.names = FALSE)
write.csv(tab03, file.path(tab_dir, "tab03_descriptives_matched_sample.csv"), row.names = FALSE)

# Tables 4 and 5.
format_corr <- function(cm) {
  out <- cm[setdiff(names(cm), "sample")]
  out$series <- label_of(out$series)
  num <- setdiff(names(out), "series")
  names(out)[match(num, names(out))] <- label_of(num)
  out[-1] <- lapply(out[-1], function(x) round(x, 3))
  names(out)[1] <- "Series"
  # The full sample has no Bitcoin column, so order by the levels present.
  present <- lvl[lvl %in% out$Series]
  out[match(present, out$Series), c("Series", present)]
}

tab04 <- format_corr(corr_full)
tab05 <- format_corr(corr_mtch)

write.csv(tab04, file.path(tab_dir, "tab04_correlation_full_sample.csv"), row.names = FALSE)
write.csv(tab05, file.path(tab_dir, "tab05_correlation_matched_sample.csv"), row.names = FALSE)

# Table 6. Each test asset against each fund's options.
tab06 <- tvb %>%
  transmute(
    `Test asset`          = test_asset,
    Fund                  = fund,
    `Benchmark option`    = benchmark,
    `Correlation, full`   = round(cor_full, 3),
    `Correlation, matched`= round(cor_matched, 3)
  ) %>%
  arrange(factor(`Test asset`, levels = lvl), Fund)

write.csv(tab06, file.path(tab_dir, "tab06_test_vs_benchmark_correlation.csv"),
          row.names = FALSE)

# Figure 1. Log scale, or Bitcoin flattens everything else onto one line.
fig01_data <- cumul %>%
  mutate(date = as_month_date(Month),
         label = factor(label, levels = lvl),
         type  = asset_type(label))

fig01 <- ggplot(fig01_data, aes(date, index, colour = label, linetype = type)) +
  geom_line(linewidth = 0.6) +
  scale_y_log10(labels = label_comma()) +
  scale_x_date(date_breaks = "2 years", date_labels = "%Y") +
  scale_linetype_manual(values = c("Benchmark option" = "solid",
                                   "Gold" = "solid", "Bitcoin" = "solid"),
                        guide = "none") +
  labs(
    title    = "Cumulative growth of A$100",
    subtitle = paste0("Matched sample, ", matched_start, " to ", matched_end,
                      ". Total returns, log scale."),
    x = NULL, y = "Index (start = 100, log scale)",
    caption = "Sources: AustralianSuper, Australian Retirement Trust, CRSP via WRDS, Yahoo Finance, RBA."
  ) +
  guides(colour = guide_legend(nrow = 3)) +
  theme_report

ggsave(file.path(fig_dir, "fig01_cumulative_growth.png"), fig01,
       width = 9, height = 6, dpi = 300)

# Figure 2. The two gold proxies overlap, so only the ASX one is plotted.
# Log axes: Bitcoin is an order of magnitude out on both.
short_label <- c(
  as_aus_shares   = "AS: Aus shares",
  as_intl_shares  = "AS: Intl shares",
  as_fixed_income = "AS: Fixed income",
  art_aus_shares  = "ART: Aus shares",
  art_intl_shares = "ART: Intl shares",
  art_bonds       = "ART: Fixed income",
  gold_asx_aud    = "Gold (GOLD.AX)",
  btc_aud         = "Bitcoin"
)

# Labels only. Spreads the cluster around 10-17% risk; points do not move.
label_nudge <- c(
  as_intl_shares  = 1.45,
  art_intl_shares = 1.18,
  gold_asx_aud    = 0.86,
  as_aus_shares   = 0.72,
  art_aus_shares  = 0.58,
  art_bonds       = 0.70
)

fig02_data <- desc %>%
  filter(series != "gold_crsp_aud") %>%
  mutate(label = factor(label, levels = lvl),
         short = short_label[series],
         type  = asset_type(label),
         label_y = ann_mean_pc *
           ifelse(series %in% names(label_nudge), label_nudge[series], 1),
         sample = factor(sample, levels = c("Full", "Matched"),
                         labels = c(paste0("Full sample: benchmarks and gold (",
                                           full_start, " to ", full_end, ")"),
                                    paste0("Matched sample: adds Bitcoin (",
                                           matched_start, " to ", matched_end, ")"))))

fig02 <- ggplot(fig02_data, aes(ann_sd_pc, ann_mean_pc, colour = type)) +
  geom_point(size = 2.8) +
  geom_text(aes(y = label_y, label = short), size = 2.9, hjust = -0.12,
            vjust = 0.4, show.legend = FALSE) +
  facet_wrap(~ sample, ncol = 1) +
  scale_colour_manual(values = c("Benchmark option" = "#2166AC",
                                 "Gold" = "#B8860B", "Bitcoin" = "#B2182B")) +
  scale_x_log10(limits = c(1.5, 400),
                breaks = c(2, 5, 10, 20, 50, 100),
                labels = c("2", "5", "10", "20", "50", "100")) +
  scale_y_log10(limits = c(0.08, 300),
                breaks = c(0.1, 0.5, 1, 2, 5, 10, 20, 50, 100),
                labels = c("0.1", "0.5", "1", "2", "5", "10", "20", "50", "100")) +
  labs(
    title    = "Annualised risk and return",
    subtitle = "Each point is one investable series. Both axes are logarithmic. Gold is the ASX-listed ETF (GOLD.AX).",
    x = "Annualised standard deviation (%, log scale)",
    y = "Annualised mean total return (%, log scale)",
      ) +
  theme_report +
  theme(legend.position = "bottom")

ggsave(file.path(fig_dir, "fig02_risk_return.png"), fig02,
       width = 9, height = 8, dpi = 300)

# Figure 3.
cor_long <- corr_mtch %>%
  select(-sample) %>%
  pivot_longer(-series, names_to = "series2", values_to = "correlation") %>%
  mutate(label1 = label_of(series), label2 = label_of(series2))

fig03 <- ggplot(cor_long, aes(factor(label1, levels = lvl),
                              factor(label2, levels = rev(lvl)),
                              fill = correlation)) +
  geom_tile(colour = "white", linewidth = 0.4) +
  geom_text(aes(label = sprintf("%.2f", correlation)), size = 2.7) +
  scale_fill_gradient2(low = "#2166AC", mid = "white", high = "#B2182B",
                       midpoint = 0, limits = c(-1, 1)) +
  labs(
    title    = "Correlation of monthly total returns",
    subtitle = paste0("Matched sample, ", matched_start, " to ", matched_end),
    x = NULL, y = NULL
  ) +
  theme_report +
  theme(axis.text.x = element_text(angle = 40, hjust = 1),
        panel.grid = element_blank(),
        legend.position = "right")

ggsave(file.path(fig_dir, "fig03_correlation_heatmap.png"), fig03,
       width = 10, height = 7.5, dpi = 300)

# Figure 4.
fig04_data <- rolling %>%
  mutate(date = as_month_date(Month),
         test_asset = factor(test_asset, levels = lvl))

fig04 <- ggplot(fig04_data, aes(date, correlation, colour = test_asset)) +
  geom_hline(yintercept = 0, colour = "grey60", linewidth = 0.4) +
  geom_line(linewidth = 0.6) +
  facet_wrap(~ fund, ncol = 1) +
  scale_x_date(date_breaks = "2 years", date_labels = "%Y") +
  coord_cartesian(ylim = c(-1, 1)) +
  scale_colour_manual(values = c("Gold, CRSP ETF (AUD)" = "#B8860B",
                                 "Gold, ASX ETF (AUD)"  = "#D9A441",
                                 "Bitcoin (AUD)"        = "#B2182B")) +
  labs(
    title    = "24-month rolling correlation with Australian shares",
        x = NULL, y = "Correlation",
      ) +
  theme_report

ggsave(file.path(fig_dir, "fig04_rolling_correlation.png"), fig04,
       width = 9, height = 7, dpi = 300)

# Figure 5.
dist_cols <- c("as_aus_shares", "as_intl_shares", "as_fixed_income",
               "art_aus_shares", "art_intl_shares", "art_bonds",
               "gold_crsp_aud", "gold_asx_aud", "btc_aud")

fig05_data <- rets %>%
  filter(Month >= matched_start, Month <= matched_end) %>%
  select(all_of(dist_cols)) %>%
  pivot_longer(everything(), names_to = "series", values_to = "ret") %>%
  filter(!is.na(ret)) %>%
  mutate(label = factor(label_of(series), levels = rev(lvl)),
         type  = asset_type(label_of(series)),
         ret_pc = 100 * ret)

fig05 <- ggplot(fig05_data, aes(label, ret_pc, fill = type)) +
  geom_hline(yintercept = 0, colour = "grey70", linewidth = 0.4) +
  geom_boxplot(outlier.size = 0.7, linewidth = 0.35, alpha = 0.85) +
  coord_flip() +
  scale_fill_manual(values = c("Benchmark option" = "#2166AC",
                               "Gold" = "#B8860B", "Bitcoin" = "#B2182B")) +
  labs(
    title    = "Distribution of monthly total returns",
    subtitle = paste0("Matched sample, ", matched_start, " to ", matched_end),
    x = NULL, y = "Monthly total return (%)"
  ) +
  theme_report

ggsave(file.path(fig_dir, "fig05_return_distributions.png"), fig05,
       width = 9, height = 6, dpi = 300)

# Figure 6. Why the matched sample is so much shorter than the benchmark history.
fig06_data <- coverage %>%
  filter(series != "rf") %>%
  mutate(label = factor(label_of(series), levels = rev(lvl)),
         type  = asset_type(label_of(series)),
         start = as_month_date(first),
         end   = as_month_date(last))

fig06 <- ggplot(fig06_data, aes(y = label)) +
  annotate("rect",
           xmin = as_month_date(matched_start), xmax = as_month_date(matched_end),
           ymin = -Inf, ymax = Inf, fill = "#B2182B", alpha = 0.10) +
  geom_segment(aes(x = start, xend = end, yend = label, colour = type),
               linewidth = 3) +
  scale_colour_manual(values = c("Benchmark option" = "#2166AC",
                                 "Gold" = "#B8860B", "Bitcoin" = "#B2182B")) +
  scale_x_date(date_breaks = "3 years", date_labels = "%Y") +
  labs(
    title    = "Coverage of each series, and the matched sample",
    subtitle = paste0("Shaded band: matched sample (", matched_start, " to ",
                      matched_end, ")"),
    x = NULL, y = NULL,
    caption = "Bitcoin sets the start of the matched sample; the end of the CRSP licence sets its end."
  ) +
  theme_report

ggsave(file.path(fig_dir, "fig06_data_coverage.png"), fig06,
       width = 9, height = 5.5, dpi = 300)

cat("  tables : ", tab_dir, "\n", sep = "")
cat("  figures: ", fig_dir, "\n", sep = "")
cat("Done.\n\n")
