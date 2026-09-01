# Installs what the pipeline needs. Run once before 00_run_all.R.
# Versions used are recorded in docs/session_info.txt.

required <- c(
  "httr2",      # Yahoo, AustralianSuper and ART requests
  "jsonlite",   # headless browser profile
  "readxl",     # RBA historical .xls
  "RPostgres",  # WRDS
  "DBI",
  "dbplyr",
  "dplyr",
  "tidyr",
  "zoo",        # rolling correlations
  "ggplot2",
  "scales",
  "here"
)

missing <- required[!(required %in% rownames(installed.packages()))]

if (length(missing) == 0) {
  cat("All required packages are already installed.\n")
} else {
  cat("Installing:", paste(missing, collapse = ", "), "\n")
  install.packages(missing, repos = "https://cloud.r-project.org")
}

cat("\nInstalled versions:\n")
for (p in required) {
  v <- tryCatch(as.character(utils::packageVersion(p)), error = function(e) "MISSING")
  cat(sprintf("  %-12s %s\n", p, v))
}

cat("\nR version:", R.version.string, "\n")
