#!/usr/bin/env Rscript
# Export a ggseg atlas package to normalized parquet tables
# Output structure (mirrors R ggseg internal structure):
#   {atlas}_core.parquet    - label, hemi, region, color (one row per label)
#   {atlas}_2d.parquet      - label, view, geometry_wkt (one row per label+view)
#   {atlas}_3d.parquet      - label, vertices_json (one row per label)
#   {atlas}_mesh.parquet    - label, vertices_json, faces_json (for subcortical)

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
  core_data <- atlas$core
  sf_data <- atlas$data$sf %||% atlas$data$ggseg
  vertices_data <- atlas$data$vertices
  meshes_data <- atlas$data$meshes

  has_output <- FALSE

  # 1. Export core table (label, hemi, region, color)
  if (!is.null(core_data)) {
    core_df <- core_data |>
      select(any_of(c("label", "hemi", "region"))) |>
      distinct()

    if (length(palette) > 0) {
      core_df$color <- as.character(palette[core_df$label])
    }

    out_file <- file.path(out_dir, paste0(atlas_name, "_core.parquet"))
    write_parquet(as.data.frame(core_df), out_file)
    cat("    Wrote:", out_file, "(", nrow(core_df), "labels )\n")
    has_output <- TRUE
  }

  # 2. Export 2D geometry table (label, view, geometry_wkt)
  if (!is.null(sf_data) && inherits(sf_data, "sf")) {
    sf_df <- sf_data |>
      mutate(geometry_wkt = st_as_text(geometry)) |>
      st_drop_geometry() |>
      select(label, view, geometry_wkt)

    out_file <- file.path(out_dir, paste0(atlas_name, "_2d.parquet"))
    write_parquet(as.data.frame(sf_df), out_file)
    cat("    Wrote:", out_file, "(", nrow(sf_df), "rows )\n")
    has_output <- TRUE
  }

  # 3. Export 3D vertices table (label, vertices_json)
  if (!is.null(vertices_data)) {
    verts_df <- vertices_data |>
      mutate(vertices_json = sapply(vertices, function(v) {
        as.character(jsonlite::toJSON(as.integer(v)))
      })) |>
      select(label, vertices_json)

    out_file <- file.path(out_dir, paste0(atlas_name, "_3d.parquet"))
    write_parquet(as.data.frame(verts_df), out_file)
    cat("    Wrote:", out_file, "(", nrow(verts_df), "labels )\n")
    has_output <- TRUE
  }

  # 4. Export mesh table for subcortical/tract atlases
  if (!is.null(meshes_data)) {
    meshes_list <- list()
    for (i in seq_len(nrow(meshes_data))) {
      row <- meshes_data[i, ]
      mesh <- row$mesh[[1]]
      meshes_list[[i]] <- data.frame(
        label = as.character(row$label),
        vertices_json = as.character(jsonlite::toJSON(mesh$vertices)),
        faces_json = as.character(jsonlite::toJSON(mesh$faces)),
        stringsAsFactors = FALSE
      )
    }
    mesh_df <- bind_rows(meshes_list)

    out_file <- file.path(out_dir, paste0(atlas_name, "_mesh.parquet"))
    write_parquet(mesh_df, out_file)
    cat("    Wrote:", out_file, "(", nrow(mesh_df), "meshes )\n")
    has_output <- TRUE
  }

  # Write metadata JSON
  if (has_output) {
    meta <- list(
      atlas = atlas$atlas %||% atlas_name,
      type = atlas_type,
      has_core = !is.null(core_data),
      has_2d = !is.null(sf_data),
      has_3d = !is.null(vertices_data),
      has_mesh = !is.null(meshes_data),
      n_labels = length(unique(core_data$label %||% character(0)))
    )
    writeLines(
      jsonlite::toJSON(meta, auto_unbox = TRUE, pretty = TRUE),
      file.path(out_dir, paste0(atlas_name, "_meta.json"))
    )
  }
}

for (atlas_name in atlas_names) {
  obj <- get(atlas_name, envir = asNamespace(package_name))
  atlas <- if (is.function(obj)) obj() else obj
  export_atlas(atlas, atlas_name, out_dir)
}

cat("Done exporting", package_name, "\n")
