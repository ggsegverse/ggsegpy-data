#!/usr/bin/env Rscript
# Export a ggseg atlas package to parquet files for Python

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
  stop("Usage: export_atlas.R <package_name>")
}

package_name <- args[1]
cat("Exporting:", package_name, "\n")

# Install from r-universe if needed
options(repos = c(
  ggsegverse = "https://ggsegverse.r-universe.dev",
  CRAN = "https://cloud.r-project.org"
))

if (!requireNamespace(package_name, quietly = TRUE)) {
  install.packages(package_name)
}

library(arrow)
library(sf)
library(dplyr)

# Create output directory
out_dir <- file.path("exports", package_name)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# Load the package
library(package_name, character.only = TRUE)

# Find brain_atlas objects in the package's data
# Get list of data objects in package
pkg_data <- data(package = package_name)$results[, "Item"]
cat("Data objects in package:", paste(pkg_data, collapse = ", "), "\n")

# Load and check each data object
atlas_names <- c()
for (obj_name in pkg_data) {
  # Load the data object
  data(list = obj_name, package = package_name, envir = environment())
  obj <- get(obj_name, envir = environment())

  if (inherits(obj, "brain_atlas")) {
    atlas_names <- c(atlas_names, obj_name)
  }
}

cat("Found atlases:", paste(atlas_names, collapse = ", "), "\n")

if (length(atlas_names) == 0) {
  cat("No brain_atlas objects found in package\n")
  quit(status = 0)
}

# Export each atlas
for (atlas_name in atlas_names) {
  # Get the atlas object
  data(list = atlas_name, package = package_name, envir = environment())
  atlas <- get(atlas_name, envir = environment())
  cat("  Exporting:", atlas_name, "\n")

  # Export 2D polygon data (ggseg sf)
  if (!is.null(atlas$data$ggseg)) {
    sf_data <- atlas$data$ggseg

    # Convert sf to data frame with WKT geometry
    df <- sf_data |>
      mutate(geometry_wkt = st_as_text(geometry)) |>
      st_drop_geometry() |>
      as.data.frame()

    out_file <- file.path(out_dir, paste0(atlas_name, "_2d.parquet"))
    write_parquet(df, out_file)
    cat("    Wrote:", out_file, "\n")
  }

  # Export 3D vertex data
  if (!is.null(atlas$data$vertices)) {
    vertices_df <- atlas$data$vertices |>
      mutate(
        vertices_json = sapply(vertices, function(v) jsonlite::toJSON(v))
      ) |>
      select(-vertices) |>
      as.data.frame()

    out_file <- file.path(out_dir, paste0(atlas_name, "_3d_vertices.parquet"))
    write_parquet(vertices_df, out_file)
    cat("    Wrote:", out_file, "\n")
  }

  # Export 3D mesh data (for subcortical/tract atlases)
  if (!is.null(atlas$data$meshes)) {
    meshes_list <- list()
    for (i in seq_len(nrow(atlas$data$meshes))) {
      row <- atlas$data$meshes[i, ]
      mesh <- row$mesh[[1]]
      meshes_list[[i]] <- data.frame(
        label = row$label,
        vertices_json = jsonlite::toJSON(mesh$vertices),
        faces_json = jsonlite::toJSON(mesh$faces)
      )
    }
    meshes_df <- bind_rows(meshes_list)

    out_file <- file.path(out_dir, paste0(atlas_name, "_3d_meshes.parquet"))
    write_parquet(meshes_df, out_file)
    cat("    Wrote:", out_file, "\n")
  }

  # Export palette
  if (!is.null(atlas$palette) && length(atlas$palette) > 0) {
    palette_df <- data.frame(
      label = names(atlas$palette),
      color = unname(atlas$palette)
    )
    out_file <- file.path(out_dir, paste0(atlas_name, "_palette.parquet"))
    write_parquet(palette_df, out_file)
    cat("    Wrote:", out_file, "\n")
  }

  # Export metadata
  meta <- list(
    atlas = atlas$atlas,
    type = atlas$type,
    labels = atlas$core$label
  )
  meta_json <- jsonlite::toJSON(meta, auto_unbox = TRUE, pretty = TRUE)
  writeLines(meta_json, file.path(out_dir, paste0(atlas_name, "_meta.json")))
}

cat("Done exporting", package_name, "\n")
