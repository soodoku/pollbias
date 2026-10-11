source("scripts/common.R")
sources <- c(
  approval = "data/bushfav_merged.csv",
  election = "data/collapsed polls_pollster.csv"
)
cleaned <- lapply(names(sources), function(dataset) {
  clean_polls(sources[[dataset]], dataset)
})
names(cleaned) <- names(sources)
polls <- bind_rows(lapply(cleaned, `[[`, "polls"))
write_csv(polls, "results/polls.csv")
saveRDS(cleaned, "cache/cleaned.rds")
print(polls |> count(dataset, exclusion))
