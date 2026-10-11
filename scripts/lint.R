source("scripts/common.R")
files <- unlist(lapply(
  c("R", "scripts", "tests"),
  list.files,
  pattern = "\\.R$",
  recursive = TRUE,
  full.names = TRUE
))
files <- c(files, "README.Rmd", "docs/audit.Rmd")
lints <- lapply(files, lintr::lint)
problems <- unlist(lints, recursive = FALSE)
if (length(problems)) {
  print(problems)
  stop("Lint checks failed")
}
