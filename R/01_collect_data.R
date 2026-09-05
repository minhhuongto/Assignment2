# Download the raw data series into data/raw/.

library(httr2)
library(dplyr)
library(readxl)
library(jsonlite)
library(RPostgres)
library(DBI)
library(dbplyr)
library(here)

# Yahoo and AustralianSuper both refuse requests without a browser User-Agent.
user_agent <- "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

get_api_data <- function(base_url,
                         endpoint,
                         query_params = list(),
                         headers = list()) {
  full_url <- paste0(base_url, "/", endpoint)

  api_request <- request(full_url) |>
    req_url_query(!!!query_params) |>
    req_headers(!!!headers)

  api_response <- req_perform(api_request)

  api_data <- resp_body_json(
    api_response,
    simplifyVector = FALSE
  )

  return(api_data)
}

download_and_save_data <- function(symbol,
                                   range = "max",
                                   interval = "1d",
                                   keep_columns = NULL,
                                   output_dir = ".") {
  cat(paste0("Downloading ", symbol, "...\n"))

  base_url <- "https://query1.finance.yahoo.com"
  endpoint <- paste0("v8/finance/chart/", symbol)

  # With range = "max" Yahoo ignores interval and returns monthly bars.
  query_params <- list(
    range = range,
    interval = interval
  )

  json_data <- get_api_data(
    base_url = base_url,
    endpoint = endpoint,
    query_params = query_params,
    headers = list("User-Agent" = user_agent)
  )

  result <- json_data$chart$result[[1]]
  timestamps <- unlist(result$timestamp)
  quote <- result$indicators$quote[[1]]

  # Convert ASX timestamps to Sydney time to avoid shifting months.
  exchange_tz <- result$meta$exchangeTimezoneName
  if (is.null(exchange_tz) || !nzchar(exchange_tz)) exchange_tz <- "UTC"

  num_col <- function(x) {
    unlist(lapply(x, function(v) if (is.null(v)) NA_real_ else as.numeric(v)))
  }

  # For GOLD.AX Yahoo returns AdjClose identical to Close and does not adjust for the split; 02_clean_merge.R handles it.
  adjclose <- result$indicators$adjclose[[1]]$adjclose

  df <- data.frame(
    Date = as.Date(as.POSIXct(timestamps, origin = "1970-01-01", tz = "UTC"),
                   tz = exchange_tz),
    Open     = num_col(quote$open),
    High     = num_col(quote$high),
    Low      = num_col(quote$low),
    Close    = num_col(quote$close),
    AdjClose = if (is.null(adjclose)) NA_real_ else num_col(adjclose),
    Volume   = num_col(quote$volume)
  )

  if (!is.null(keep_columns)) {
    missing <- setdiff(keep_columns, names(df))
    if (length(missing) > 0) {
      stop(symbol, " is missing column(s): ", paste(missing, collapse = ", "))
    }
    df <- df[keep_columns]
  }

  output_file <- file.path(output_dir, paste0(symbol, ".csv"))

  write.csv(df, output_file, row.names = FALSE)
  cat(paste0("Saved ", nrow(df), " rows to ", output_file, "\n\n"))

  return(df)
}

find_chromium <- function() {
  candidates <- c(
    Sys.getenv("CHROMOTE_CHROME"),
    file.path(Sys.getenv("ProgramFiles"), "Google/Chrome/Application/chrome.exe"),
    file.path(Sys.getenv("ProgramFiles(x86)"), "Google/Chrome/Application/chrome.exe"),
    file.path(Sys.getenv("ProgramFiles(x86)"), "Microsoft/Edge/Application/msedge.exe"),
    file.path(Sys.getenv("ProgramFiles"), "Microsoft/Edge/Application/msedge.exe")
  )
  candidates <- candidates[nzchar(candidates)]
  candidates <- candidates[file.exists(candidates)]
  if (!length(candidates)) NA_character_ else candidates[1]
}

stop_browser <- function(profile_tag) {
  script <- sprintf(
    "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*%s*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }",
    profile_tag)
  suppressWarnings(system2("powershell", c("-NoProfile", "-Command", shQuote(script, type = "cmd")),
                           stdout = FALSE, stderr = FALSE))
}

browser_download <- function(warm_url, file_url, dest_file, wait_sec = 120) {
  chromium <- find_chromium()
  if (is.na(chromium)) return(FALSE)

  dest_dir <- dirname(dest_file)
  profile_tag <- paste0("rdl", sample(100000:999999, 1))
  profile <- file.path(tempdir(), profile_tag)
  dir.create(file.path(profile, "Default"), recursive = TRUE, showWarnings = FALSE)

  # Download to output_dir rather than the user's Downloads folder.
  prefs <- list(download = list(
    default_directory = normalizePath(dest_dir, winslash = "\\", mustWork = TRUE),
    prompt_for_download = FALSE))
  writeLines(jsonlite::toJSON(prefs, auto_unbox = TRUE),
             file.path(profile, "Default", "Preferences"))

  q <- function(x) shQuote(x, type = "cmd")
  args <- c("--headless=new", "--disable-gpu", "--no-first-run", "--no-default-browser-check",
            paste0("--user-data-dir=", q(profile)),
            # The default headless agent says "HeadlessChrome" and is blocked.
            paste0("--user-agent=", q(user_agent)),
            "--window-size=1920,1080",
            "--disable-blink-features=AutomationControlled")

  if (file.exists(dest_file)) unlink(dest_file)

  # Open the website first to save the required cookies.
  system2(chromium, c(args, "--virtual-time-budget=30000", "--dump-dom", q(warm_url)),
          stdout = FALSE, stderr = FALSE)

  # Download the file in the background.
  system2(chromium, c(args, q(file_url)), stdout = FALSE, stderr = FALSE, wait = FALSE)

  waited <- 0
  last_size <- -1
  repeat {
    Sys.sleep(2)
    waited <- waited + 2
    in_progress <- length(list.files(dest_dir, pattern = "crdownload$")) > 0
    size_now <- if (file.exists(dest_file)) file.size(dest_file) else -1
    if (!in_progress && size_now > 0 && size_now == last_size) break
    last_size <- size_now
    if (waited >= wait_sec) break
  }

  stop_browser(profile_tag)
  unlink(profile, recursive = TRUE, force = TRUE)

  file.exists(dest_file) && file.size(dest_file) > 0
}

# Cumulative daily returns for AustralianSuper's investment options.
download_australiansuper_rates <- function(start = "01/07/2008",
                                           end = format(Sys.Date(), "%d/%m/%Y"),
                                           output_dir = ".") {
  cat("Downloading AustralianSuper daily rates...\n")

  output_file <- file.path(output_dir, "AustralianSuper_cumulative_daily_rates.csv")
  file_name <- basename(output_file)

  query <- list(
    start                 = start,
    end                   = end,
    cumulative            = "True",
    superType             = "super",
    truncateDecimalPlaces = "True",
    outputFilename        = file_name
  )

  downloaded <- tryCatch({
    api_response <- request("https://www.australiansuper.com/api/graphs/dailyrates/download/") |>
      req_url_query(!!!query) |>
      req_headers("User-Agent" = user_agent, "Accept" = "text/csv,*/*") |>
      req_perform()
    writeBin(resp_body_raw(api_response), output_file)
    cat("  Downloaded directly.\n")
    TRUE
  }, error = function(e) FALSE)

  if (!downloaded) {
    cat("  Direct request refused, retrying through a headless browser...\n")
    file_url <- request("https://www.australiansuper.com/api/graphs/dailyrates/download/") |>
      req_url_query(!!!query) |>
      (\(r) r$url)()
    downloaded <- browser_download(
      warm_url  = "https://www.australiansuper.com/compare-us/our-performance",
      file_url  = file_url,
      dest_file = output_file
    )
    if (downloaded) cat("  Downloaded via the browser.\n")
  }

  if (!downloaded && !file.exists(output_file)) {
    stop("Could not download the file and there is no local copy. Open this URL in a\n",
         "  browser and save the result to ", output_file, ":\n  ",
         "https://www.australiansuper.com/api/graphs/dailyrates/download/",
         "?start=", start, "&end=", end,
         "&cumulative=True&superType=super&truncateDecimalPlaces=True",
         "&outputFilename=", file_name)
  }

  if (!downloaded) {
    cat(paste0("  Download failed; reusing the existing file.\n"))
  }

  df <- read.csv(output_file, check.names = FALSE, stringsAsFactors = FALSE)
  df$`Rate Date` <- as.Date(df$`Rate Date`)

  cat(paste0("  ", nrow(df), " rows, ", min(df$`Rate Date`), " to ",
             max(df$`Rate Date`), "\n"))
  cat(paste0("Saved to ", output_file, "\n\n"))

  return(df)
}

# Table F11 is split in two: the historical sheet ends Dec 2009, the current
# file starts Jan 2010.
download_rba_audusd <- function(start_date = NULL,
                                output_dir = ".") {
  cat("Downloading RBA AUD/USD...\n")

  url_old <- "https://www.rba.gov.au/statistics/tables/xls-hist/f11hist-1969-2009.xls"
  url_new <- "https://www.rba.gov.au/statistics/tables/csv/f11-data.csv"

  old_file <- tempfile(fileext = ".xls")
  download.file(url_old, destfile = old_file, mode = "wb", quiet = TRUE)

  # 10 metadata rows precede the header. FXRUSD is the AUD/USD rate.
  rba_old <- read_excel(
    old_file,
    sheet = "Data",
    skip = 10
  ) %>%
    transmute(
      date = as.Date(`Series ID`),
      audusd = as.numeric(FXRUSD)
    )

  rba_new <- read.csv(
    url_new,
    skip = 10,
    check.names = FALSE,
    stringsAsFactors = FALSE
  ) %>%
    transmute(
      date = as.Date(`Series ID`, format = "%d-%b-%Y"),
      audusd = as.numeric(FXRUSD)
    )

  audusd <- bind_rows(
    rba_old,
    rba_new
  ) %>%
    arrange(date)

  if (!is.null(start_date)) {
    audusd <- filter(audusd, date >= as.Date(start_date))
  }

  output_file <- file.path(output_dir, "AUD_USD_RBA.csv")

  write.csv(audusd, output_file, row.names = FALSE)

  cat(paste0("  ", min(audusd$date), " to ", max(audusd$date),
             " | duplicate months: ", sum(duplicated(format(audusd$date, "%Y-%m"))),
             ", missing rates: ", sum(is.na(audusd$audusd)), "\n"))
  cat(paste0("Saved ", nrow(audusd), " rows to ", output_file, "\n\n"))

  return(audusd)
}

# ART unit prices.
# Fund_codes: 44 Australian Shares Index, 32 International Shares Unhedged,
# 23 Bonds Index.
download_art_unit_prices <- function(product_code = "SOL",
                                     fund_codes = c("44", "32", "23"),
                                     subscription_key = Sys.getenv("ART_SUBSCRIPTION_KEY"),
                                     output_dir = ".") {
  cat("Downloading Australian Retirement Trust unit prices...\n")

  if (!nzchar(subscription_key)) {
    stop("No ART subscription key. Set ART_SUBSCRIPTION_KEY in .Renviron ",
         "(see the Credentials section of README.md).")
  }

  base_url <- "https://api.art.com.au/integration/publicweb/v1"

  api_headers <- list(
    "x-art-subscription-key"       = subscription_key,
    "x-art-initiating-application" = "PublicWeb",
    "x-art-correlation-id"         = "00000000-0000-0000-0000-000000000000"
  )

  funds <- get_api_data(
    base_url     = base_url,
    endpoint     = "investment/product/funds",
    query_params = list(productCodes = product_code),
    headers      = api_headers
  )

  effective <- get_api_data(
    base_url = base_url,
    endpoint = paste0("investment/unit-price/product/", product_code, "/effective-dates"),
    headers  = api_headers
  )
  from_date <- substr(effective$effectiveDates$minDate, 1, 10)
  to_date   <- substr(effective$effectiveDates$maxDate, 1, 10)

  old_locale <- Sys.getlocale("LC_TIME")
  on.exit(Sys.setlocale("LC_TIME", old_locale), add = TRUE)
  Sys.setlocale("LC_TIME", "C")

  all_prices <- list()

  available <- unlist(lapply(funds$groups, function(g) sapply(g$funds, `[[`, "code")))
  missing <- setdiff(fund_codes, available)
  if (length(missing) > 0) {
    stop("Unknown fund code(s): ", paste(missing, collapse = ", "),
         ". Available: ", paste(available, collapse = ", "))
  }

  for (group in funds$groups) {
    for (fund in group$funds) {
      if (!is.null(fund_codes) && !(fund$code %in% fund_codes)) next

      csv_text <- tryCatch({
        request(paste0(base_url, "/investment/unit-price/history/data")) |>
          req_url_query(fundCodes = fund$code, fromDate = from_date, toDate = to_date) |>
          req_headers(!!!api_headers) |>
          req_perform() |>
          resp_body_string()
      }, error = function(e) {
        cat(paste0("  ", fund$name, ": ", conditionMessage(e), "\n"))
        NULL
      })

      if (is.null(csv_text)) next

      rows <- read.csv(text = csv_text, skip = 1, strip.white = TRUE,
                       stringsAsFactors = FALSE)

      if (nrow(rows) == 0) next

      all_prices[[length(all_prices) + 1]] <- data.frame(
        Date       = as.Date(rows[[1]], format = "%d %b %Y"),
        Group      = group$name,
        FundCode   = fund$code,
        FundName   = fund$name,
        EntryPrice = as.numeric(rows[[2]]),
        ExitPrice  = as.numeric(rows[[3]])
      )
    }
  }

  df <- do.call(rbind, all_prices)
  df <- df[order(df$FundName, df$Date), ]

  output_file <- file.path(output_dir, "AustralianRetirementTrust_unit_prices.csv")

  write.csv(df, output_file, row.names = FALSE)

  cat(paste0("  ", length(all_prices), " options, ", min(df$Date), " to ",
             max(df$Date), " | zero-price rows: ", sum(df$EntryPrice == 0), "\n"))
  cat(paste0("Saved ", nrow(df), " rows to ", output_file, "\n\n"))

  return(df)
}

# Use SPDR Gold Trust (GLD, permno 90448) in CRSP.
# Username comes from WRDS_USER, password from the local pgpass file.
download_wrds_gold <- function(user = Sys.getenv("WRDS_USER"),
                               permno = 90448,
                               start_date = "2004-11-18",
                               end_date = format(Sys.Date(), "%Y-%m-%d"),
                               output_dir = ".") {
  cat("Downloading GOLD (USD) from WRDS...\n")

  if (!nzchar(user)) {
    stop("No WRDS username. Set one with: Sys.setenv(WRDS_USER = \"your_username\")")
  }

  wrds <- dbConnect(
    Postgres(),
    host            = "wrds-pgdata.wharton.upenn.edu",
    port            = 9737,
    dbname          = "wrds",
    sslmode         = "require",
    user            = user,
    connect_timeout = 30
  )
  on.exit(dbDisconnect(wrds), add = TRUE)

  gold <- tbl(wrds, in_schema("crsp", "dsf")) |>
    select(permno, date, prc) |>
    filter(
      permno == !!permno,
      date >= !!start_date,
      date <= !!end_date
    ) |>
    arrange(date) |>
    collect()

  if (nrow(gold) == 0) {
    stop("WRDS returned no rows for permno ", permno, " between ",
         start_date, " and ", end_date)
  }

  # prc is negative when the day closed without a trade (bid/ask midpoint).
  # Sign is kept here; 02_clean_merge.R takes the magnitude.
  df <- data.frame(
    Date   = as.Date(gold$date),
    Permno = gold$permno,
    Prc    = gold$prc
  )

  output_file <- file.path(output_dir, "GOLD_USD_GLD.csv")

  write.csv(df, output_file, row.names = FALSE)

  cat(paste0("  ", min(df$Date), " to ", max(df$Date),
             " | missing prices: ", sum(is.na(df$Prc)), "\n"))
  cat(paste0("Saved ", nrow(df), " rows to ", output_file, "\n\n"))

  return(df)
}

# Cash rate target, table F1.1 series FIRMMCRT, annual per cent. 
download_rba_cash_rate <- function(output_dir = ".") {
  cat("Downloading RBA cash rate...\n")

  url <- "https://www.rba.gov.au/statistics/tables/csv/f1.1-data.csv"

  rates <- read.csv(url, skip = 10, check.names = FALSE, stringsAsFactors = FALSE)

  df <- data.frame(
    date      = as.Date(rates$`Series ID`, format = "%d/%m/%Y"),
    cash_rate = suppressWarnings(as.numeric(rates$FIRMMCRT))
  )
  df <- df[!is.na(df$date) & !is.na(df$cash_rate), ]
  df <- df[order(df$date), ]

  output_file <- file.path(output_dir, "RBA_cash_rate.csv")

  write.csv(df, output_file, row.names = FALSE)

  cat(paste0("  ", min(df$date), " to ", max(df$date),
             " | duplicate months: ", sum(duplicated(format(df$date, "%Y-%m"))), "\n"))
  cat(paste0("Saved ", nrow(df), " rows to ", output_file, "\n\n"))

  return(df)
}


raw_dir <- here("data", "raw")
if (!dir.exists(raw_dir)) dir.create(raw_dir, recursive = TRUE)

# One failure should not stop the remaining downloads.
for (sym in c("GOLD.AX", "BTC-AUD")) {
  tryCatch({
    download_and_save_data(symbol = sym, output_dir = raw_dir)
  }, error = function(e) {
    cat(paste0("Failed to download ", sym, ": ", conditionMessage(e), "\n\n"))
  })
}

super_rates <- download_australiansuper_rates(output_dir = raw_dir)

audusd <- download_rba_audusd(output_dir = raw_dir)

cash_rate <- download_rba_cash_rate(output_dir = raw_dir)

art_unit_prices <- download_art_unit_prices(output_dir = raw_dir)

gold_usd <- tryCatch({
  download_wrds_gold(output_dir = raw_dir)
}, error = function(e) {
  cat(paste0("Failed to download GOLD (USD) from WRDS: ", conditionMessage(e), "\n"))
  cat("  This step needs a WRDS account with a CRSP subscription. See README.md.\n\n")
  NULL
})

cat("Raw data written to", raw_dir, "\n")
