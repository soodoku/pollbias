source("scripts/common.R")
source("R/benchmark.R")
cleaned <- readRDS("cache/cleaned.rds")
summary <- list()
comparisons <- list()
for (dataset_name in names(cleaned)) {
  item <- cleaned[[dataset_name]]
  raw <- item$raw
  data <- item$polls |> filter(is.na(exclusion))
  week_origin <- as.Date(if (dataset_name == "approval") "2001-01-01" else "2007-01-01")
  week_checks <- item$polls |>
    mutate(
      original_week = suppressWarnings(as.numeric(raw$week)),
      reconstructed_week = as.integer(start_date - week_origin) %/% 7,
      discrepancy = original_week - reconstructed_week
    ) |>
    select(source_row, house, start_date, end_date, original_week, reconstructed_week, discrepancy)
  write_csv(week_checks, paste0("results/", dataset_name, "_week_checks.csv"))
  summary[[dataset_name]] <- tibble(
    dataset = dataset_name,
    source_polls = nrow(raw),
    usable_polls = nrow(data),
    houses = n_distinct(data$house),
    excluded_polls = nrow(raw) - nrow(data),
    missing_sample_size = sum(is.na(data$sample_size)),
    unknown_screen = sum(data$screen == "unknown"),
    first_date = min(data$start_date),
    last_date = max(data$end_date),
    exact_duplicate_rows = sum(duplicated(select(raw, -source_row))),
    duplicate_survey_keys = sum(duplicated(select(
      data,
      house,
      geography,
      start_date,
      end_date
    ))),
    overlapping_polls_removed = nrow(data) - nrow(thin_overlapping(data))
  )
  benchmark <- fit_benchmark(data)
  write_csv(
    benchmark$estimates,
    paste0("results/", dataset_name, "_benchmark.csv")
  )
  write_csv(
    benchmark$components,
    paste0("results/", dataset_name, "_components.csv")
  )
  write_csv(
    overlap_support(data),
    paste0("results/", dataset_name, "_overlap.csv")
  )
  original_outcome <- if (dataset_name == "election") {
    as.numeric(raw$mccain)
  } else {
    as.numeric(raw$approve)
  }
  original_rasmussen <- trimws(raw$organization) == "Rasmussen"
  original_difference <- mean(original_outcome[original_rasmussen]) -
    mean(original_outcome[!original_rasmussen])
  data <- data |>
    mutate(
      is_rasmussen = as.numeric(house == "Rasmussen"),
      comparison_outcome = if (dataset_name == "election") mccain else outcome
    )
  timing <- lm(
    comparison_outcome ~ is_rasmussen + splines::ns(time, df = 20),
    data
  )
  adjusted <- if (dataset_name == "election") {
    lm(
      comparison_outcome ~ is_rasmussen +
        factor(geography) +
        splines::ns(time, df = 20),
      data
    )
  } else {
    timing
  }
  comparisons[[dataset_name]] <- tibble(
    dataset = dataset_name,
    original_raw_gap = original_difference,
    cleaned_raw_gap = mean(data$comparison_outcome[data$is_rasmussen == 1]) -
      mean(data$comparison_outcome[data$is_rasmussen == 0]),
    time_adjusted_gap = unname(coef(timing)["is_rasmussen"]),
    time_geography_adjusted_gap = unname(coef(adjusted)["is_rasmussen"])
  )
  duplicates <- data |>
    add_count(house, geography, start_date, end_date, name = "key_count") |>
    filter(key_count > 1)
  write_csv(duplicates, paste0("results/", dataset_name, "_duplicate_keys.csv"))
  p <- ggplot(
    data,
    aes(midpoint, comparison_outcome, color = house == "Rasmussen")
  ) +
    geom_point(alpha = 0.2, size = 0.7) +
    geom_smooth(
      method = "gam",
      formula = y ~ s(x, bs = "cs"),
      linewidth = 0.6
    ) +
    scale_color_manual(
      values = c("#777777", "#A9473A"),
      labels = c("Other", "Rasmussen")
    ) +
    labs(
      x = NULL,
      y = if (dataset_name == "election") {
        "McCain support (%)"
      } else {
        "Bush approval (%)"
      },
      color = NULL,
      caption = "Descriptive pooled trends; election polls mix states and national samples."
    ) +
    theme_minimal(base_size = 11) +
    theme(legend.position = "top")
  ggsave(
    paste0("figs/", dataset_name, "_descriptive.png"),
    p,
    width = 9,
    height = 4,
    dpi = 160
  )
}
write_csv(bind_rows(summary), "results/data_summary.csv")
write_csv(bind_rows(comparisons), "results/rasmussen_comparisons.csv")
print(bind_rows(summary))
print(bind_rows(comparisons))
