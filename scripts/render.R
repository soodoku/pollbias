source("scripts/common.R")
source("R/models.R")
summaries <- read_csv("results/data_summary.csv", show_col_types = FALSE)
for (dataset_name in summaries$dataset) {
  estimates <- read_csv(
    paste0("results/", dataset_name, "_houses.csv"),
    show_col_types = FALSE
  )
  overlap <- read_csv(
    paste0("results/", dataset_name, "_overlap.csv"),
    show_col_types = FALSE
  )
  estimates <- estimates |>
    left_join(overlap, by = "house", relationship = "one-to-one") |>
    mutate(
      support = case_when(
        !reference ~ "sparse",
        shared_cell_fraction < 0.5 ~ "limited overlap",
        TRUE ~ "supported"
      )
    )
  write_csv(estimates, paste0("results/", dataset_name, "_estimates.csv"))
  shown <- filter(estimates, reference) |>
    arrange(estimate) |>
    mutate(house = factor(house, levels = house))
  p <- ggplot(shown, aes(estimate, house)) +
    geom_vline(xintercept = 0, color = "#888888", linetype = "dashed") +
    geom_segment(
      aes(x = lower, xend = upper, yend = house),
      color = "#315B76"
    ) +
    geom_point(color = "#315B76", size = 1.8) +
    scale_y_discrete(labels = function(x) stringr::str_wrap(x, width = 38)) +
    labs(
      x = "Relative house effect (percentage points)",
      y = NULL,
      title = if (dataset_name == "approval") {
        "Bush approval"
      } else {
        "2008 election: McCain minus Obama"
      },
      subtitle = "Posterior mean and 95% credible interval",
      caption = "Reference: equal-weight average of houses with ≥10 polls in ≥3 months."
    ) +
    theme_minimal(base_size = 11) +
    theme(panel.grid.major.y = element_blank())
  ggsave(
    paste0("figs/", dataset_name, "_houses.png"),
    p,
    width = 9,
    height = max(5, nrow(shown) * 0.24 + 1.5),
    dpi = 180
  )
}
break_predictions <- read_csv("results/approval_break_predictions.csv", show_col_types = FALSE)
trend <- break_predictions |>
  group_by(midpoint, model) |>
  summarise(fitted = mean(fitted), .groups = "drop")
p <- ggplot() +
  geom_point(
    data = distinct(break_predictions, source_row, midpoint, observed),
    aes(midpoint, observed), color = "#888888", alpha = 0.6, size = 1.4
  ) +
  geom_line(data = trend, aes(midpoint, fitted, color = model), linewidth = 0.8) +
  geom_vline(xintercept = as.Date("2001-09-11"), linetype = "dotted") +
  scale_color_manual(values = c("With break" = "#315B76", "Smooth only" = "#9C6B3E")) +
  scale_x_date(date_labels = "%b %d") +
  labs(
    x = "2001", y = "Bush approval (%)", color = NULL,
    caption = "Dots: reported polls. Lines: mean fitted values for houses polled on each date."
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "top")
ggsave("figs/approval_break_check.png", p, width = 8, height = 4.5, dpi = 180)
for (path in c("README.Rmd", "docs/audit.Rmd")) {
  rmarkdown::render(
    path,
    output_format = rmarkdown::github_document(
      html_preview = FALSE, md_extensions = "-implicit_figures"
    ),
    knit_root_dir = normalizePath("."), envir = new.env(), quiet = TRUE
  )
}
