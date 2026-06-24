# Standalone testthat runner (this is a Quarto project, not an R package,
# so there's no DESCRIPTION-driven `R CMD check` to wire this into).
# Run from the curator_table_r/ directory with: Rscript tests/testthat.R

library(testthat)

source(file.path("R", "config.R"))
source(file.path("R", "data.R"))

test_dir("tests/testthat", reporter = "summary")
