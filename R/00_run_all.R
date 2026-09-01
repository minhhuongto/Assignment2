# Runs the whole pipeline. Open Assignment2.Rproj first so the working
# directory is the project root, then source this file.
#
#   01_collect_data.R    sources          -> data/raw/
#   02_clean_merge.R     data/raw/        -> data/processed/
#   03_analysis.R        panel            -> results
#   04_tables_figures.R  results          -> output/
#
# Allow 3-5 minutes. Most of that is step 01: ART allows only one investment
# option per request, and AustralianSuper needs a headless browser.
# See README.md for the data access requirements.

library(here)

steps <- c(
  "01_collect_data.R",
  "02_clean_merge.R",
  "03_analysis.R",
  "04_tables_figures.R"
)

started <- Sys.time()

for (step in steps) {
  cat("\n================================================================\n")
  cat("Running ", step, "\n", sep = "")
  cat("================================================================\n")
  source(here("R", step), echo = FALSE)
}

# No data is committed, so this file and coverage_report.csv are how a
# reproduction is checked against ours.
writeLines(
  c(paste("Pipeline run:", format(started, "%Y-%m-%d %H:%M:%S")),
    paste("Completed   :", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    "",
    capture.output(sessionInfo())),
  here("docs", "session_info.txt")
)

cat("\nPipeline finished in ",
    round(as.numeric(difftime(Sys.time(), started, units = "mins")), 1),
    " minutes.\n", sep = "")
cat("Environment recorded in docs/session_info.txt\n")
