#!/usr/bin/env Rscript
# Export a ggseg atlas package to parquet files for Python
# Output: atlas_2d.parquet (sf + palette as color column), atlas_3d.parquet (vertices or meshes)

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

# Define null coalescing operator
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
 cat("No brain_atlas objects found in package\n")
 quit(status = 0)
}

# Helper to export an atlas object
export_atlas <- function(atlas, atlas_name, out_dir) {
 cat("  Exporting:", atlas_name, "\n")

 # Get palette for adding color column
 palette <- atlas$palette %||% list()

 # Export 2D polygon data (sf in new format, ggseg in old format)
 sf_data <- NULL
 if (!is.null(atlas$data$sf)) {
   sf_data <- atlas$data$sf
 } else if (!is.null(atlas$data$ggseg)) {
   sf_data <- atlas$data$ggseg
 }

 if (!is.null(sf_data) && inherits(sf_data, "sf")) {
   # Add color column from palette if not present
   if (!"color" %in% names(sf_data) && length(palette) > 0) {
     sf_data$color <- palette[sf_data$label]
   }

   df <- sf_data |>
     mutate(geometry_wkt = st_as_text(geometry)) |>
     st_drop_geometry() |>
     as.data.frame()

   out_file <- file.path(out_dir, paste0(atlas_name, ".parquet"))
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

   # Add color from palette
   if (length(palette) > 0) {
     vertices_df$color <- palette[vertices_df$label]
   }

   out_file <- file.path(out_dir, paste0(atlas_name, "_3d.parquet"))
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
       faces_json = jsonlite::toJSON(mesh$faces),
       color = palette[row$label] %||% NA_character_
     )
   }
   meshes_df <- bind_rows(meshes_list)

   out_file <- file.path(out_dir, paste0(atlas_name, "_3d.parquet"))
   write_parquet(meshes_df, out_file)
   cat("    Wrote:", out_file, "\n")
 }

 # Export metadata as JSON
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
