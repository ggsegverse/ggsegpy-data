#!/usr/bin/env Rscript
# Export a ggseg atlas package to a single unified parquet file
# Contains: label, hemi, region, view, geometry_wkt, vertices_json, color

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
  stop("Usage: export_atlas.R <package_name>")
}

package_name <- args[1]
cat("Exporting:", package_name, "\n")

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
library(tidyr)

`%||%` <- function(x, y) if (is.null(x)) y else x

out_dir <- file.path("exports", package_name)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

library(package_name, character.only = TRUE)

pkg_exports <- ls(paste0("package:", package_name))
cat("Package exports:", paste(pkg_exports, collapse = ", "), "\n")

atlas_names <- c()
for (obj_name in pkg_exports) {
  obj <- get(obj_name, envir = asNamespace(package_name))
  if (is.function(obj)) {
    tryCatch({
      result <- obj()
      if (inherits(result, "brain_atlas") || inherits(result, "ggseg_atlas")) {
        atlas_names <- c(atlas_names, obj_name)
      }
    }, error = function(e) {})
  } else if (inherits(obj, "brain_atlas") || inherits(obj, "ggseg_atlas")) {
    atlas_names <- c(atlas_names, obj_name)
  }
}

cat("Found atlases:", paste(atlas_names, collapse = ", "), "\n")

if (length(atlas_names) == 0) {
  cat("No brain_atlas objects found\n")
  quit(status = 0)
}

export_atlas <- function(atlas, atlas_name, out_dir) {
  cat("  Exporting:", atlas_name, "\n")

  palette <- atlas$palette %||% list()
  atlas_type <- atlas$type %||% "unknown"

  # Get 2D sf data
  sf_data <- atlas$data$sf %||% atlas$data$ggseg

  # Get 3D data (vertices or meshes)
  vertices_data <- atlas$data$vertices
  meshes_data <- atlas$data$meshes

  if (!is.null(sf_data) && inherits(sf_data, "sf")) {
    # Start with 2D data
    df <- sf_data |>
      mutate(geometry_wkt = st_as_text(geometry)) |>
      st_drop_geometry()

    # Add color from palette if not present
    if (!"color" %in% names(df) && length(palette) > 0) {
      df$color <- as.character(palette[df$label])
    }

    # Add 3D vertices (join by label)
    if (!is.null(vertices_data)) {
      verts_df <- vertices_data |>
        mutate(vertices_json = sapply(vertices, function(v) {
          as.character(jsonlite::toJSON(as.integer(v)))
        })) |>
        select(label, vertices_json)

      df <- df |> left_join(verts_df, by = "label")
    }

    # Ensure standard column order
    core_cols <- c("label", "hemi", "region")
    other_cols <- setdiff(names(df), core_cols)
    df <- df |> select(all_of(c(core_cols, other_cols)))

    # Add metadata as attributes (will be in parquet schema metadata)
    attr(df, "atlas_name") <- atlas$atlas %||% atlas_name
    attr(df, "atlas_type") <- atlas_type

    out_file <- file.path(out_dir, paste0(atlas_name, ".parquet"))
    write_parquet(as.data.frame(df), out_file)
    cat("    Wrote:", out_file, "\n")

  } else if (!is.null(meshes_data)) {
    # Subcortical/tract atlas with meshes only
    meshes_list <- list()
    for (i in seq_len(nrow(meshes_data))) {
      row <- meshes_data[i, ]
      mesh <- row$mesh[[1]]
      meshes_list[[i]] <- data.frame(
        label = as.character(row$label),
        hemi = as.character(row$hemi %||% NA),
        region = as.character(row$region %||% row$label),
        vertices_json = as.character(jsonlite::toJSON(mesh$vertices)),
        faces_json = as.character(jsonlite::toJSON(mesh$faces)),
        color = as.character(palette[row$label] %||% NA),
        stringsAsFactors = FALSE
      )
    }
    df <- bind_rows(meshes_list)

    out_file <- file.path(out_dir, paste0(atlas_name, ".parquet"))
    write_parquet(df, out_file)
    cat("    Wrote:", out_file, "\n")
  }

  # Write metadata JSON
  meta <- list(
    atlas = atlas$atlas %||% atlas_name,
    type = atlas_type,
    has_2d = !is.null(sf_data),
    has_3d_vertices = !is.null(vertices_data),
    has_3d_meshes = !is.null(meshes_data),
    n_labels = length(unique(atlas$core$label %||% character(0)))
  )
  writeLines(
    jsonlite::toJSON(meta, auto_unbox = TRUE, pretty = TRUE),
    file.path(out_dir, paste0(atlas_name, "_meta.json"))
  )
}

for (atlas_name in atlas_names) {
  obj <- get(atlas_name, envir = asNamespace(package_name))
  atlas <- if (is.function(obj)) obj() else obj
  export_atlas(atlas, atlas_name, out_dir)
}

cat("Done exporting", package_name, "\n")
