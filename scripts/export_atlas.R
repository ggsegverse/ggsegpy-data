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

# Define null coalescing operator if not available
`%||%` <- function(x, y) if (is.null(x)) y else x

# Create output directory
out_dir <- file.path("exports", package_name)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# Load the package
library(package_name, character.only = TRUE)

# Get all exports from the package
pkg_exports <- ls(paste0("package:", package_name))
cat("Package exports:", paste(pkg_exports, collapse = ", "), "\n")

# Find atlas functions/objects
atlas_names <- c()
for (obj_name in pkg_exports) {
  obj <- get(obj_name, envir = asNamespace(package_name))

  # Check if it's a function that returns brain_atlas
  if (is.function(obj)) {
    tryCatch({
      result <- obj()
      if (inherits(result, "brain_atlas") || inherits(result, "ggseg_atlas")) {
        atlas_names <- c(atlas_names, obj_name)
      }
    }, error = function(e) {
      # Function might need arguments, skip
    })
  } else if (inherits(obj, "brain_atlas") || inherits(obj, "ggseg_atlas")) {
    # Direct brain_atlas object
    atlas_names <- c(atlas_names, obj_name)
  }
}

cat("Found atlases:", paste(atlas_names, collapse = ", "), "\n")

if (length(atlas_names) == 0) {
  cat("No brain_atlas objects found in package\n")
  quit(status = 0)
}

# Helper to export an atlas object
export_atlas <- function(atlas, atlas_name, out_dir) {
  cat("  Exporting:", atlas_name, "\n")

  # Export 2D polygon data
  sf_data <- NULL
  if (!is.null(atlas$data$ggseg)) {
    sf_data <- atlas$data$ggseg
  } else if (inherits(atlas, "sf")) {
    sf_data <- atlas
  } else if (!is.null(atlas$data) && inherits(atlas$data, "sf")) {
    sf_data <- atlas$data
  }

  if (!is.null(sf_data) && inherits(sf_data, "sf")) {
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

  # Export 3D mesh data
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
    atlas = atlas$atlas %||% atlas_name,
    type = atlas$type %||% "unknown"
  )
  if (!is.null(atlas$core$label)) {
    meta$labels <- atlas$core$label
  }
  meta_json <- jsonlite::toJSON(meta, auto_unbox = TRUE, pretty = TRUE)
  writeLines(meta_json, file.path(out_dir, paste0(atlas_name, "_meta.json")))
}

# Export each atlas
for (atlas_name in atlas_names) {
  obj <- get(atlas_name, envir = asNamespace(package_name))

  if (is.function(obj)) {
    atlas <- obj()
  } else {
    atlas <- obj
  }

  export_atlas(atlas, atlas_name, out_dir)
}

cat("Done exporting", package_name, "\n")
