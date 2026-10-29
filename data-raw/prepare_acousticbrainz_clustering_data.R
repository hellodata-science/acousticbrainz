# The acoustic_brainz dataset uses multiple data files that you'll need to retrieve
#
# Data sources:
# - AcousticBrainz low-level feature dumps (CC0):
#   https://acousticbrainz.org/download "Feature downloads"
#     1. acousticbrainz-lowlevel-features-20220623-lowlevel.tar.zst
#     2. acousticbrainz-lowlevel-features-20220623-rhythm.tar.zst
#     3. acousticbrainz-lowlevel-features-20220623-tonal.tar.zst
# - Canonical MusicBrainz data dumps (CC0):
#   https://metabrainz.org/datasets/download "MusicBrainz Canonical Data Dumps"
#     1. musicbrainz-canonical-dump-20261003-080003.tar.zst
#     The current canonical dump is dated October 15, 2026 while the AcousticBrainz feature data stopped in June 2022.
#
# Before running this script, download and extract these four archives into
# data-raw/unextracted-files/:
#
# After extraction, data-raw/acousticbrainz/ must contain these five CSV files:
#
# - acousticbrainz-lowlevel-features-20220623-lowlevel.csv
# - acousticbrainz-lowlevel-features-20220623-rhythm.csv
# - acousticbrainz-lowlevel-features-20220623-tonal.csv
# - canonical_recording_redirect.csv
# - canonical_musicbrainz_data.csv
#
# The source files contain tens of millions of rows. DuckDB reads and filters
# them without loading the complete files into R's memory.

library(tidyverse)
library(DBI)
library(dbplyr)
library(duckdb)
library(fs)
library(here)

# Configuration -----------------------------------------------------------

raw_data_dir <- here("data-raw")
artist_pool_file <- here("data-raw", "artists-to-select.csv")
output_file <- here("data", "acousticbrainz_songs.csv")

# These caps prevent a few prolific artists from dominating the dataset.
max_songs_per_artist <- 25L
song_seed <- 20260925L

# Locate and validate source files ----------------------------------------

find_one_file <- function(pattern, description) {
  matches <- dir_ls(
    raw_data_dir,
    recurse = TRUE,
    type = "file",
    regexp = pattern
  )

  if (length(matches) != 1L) {
    cli::cli_abort(c(
      "Expected exactly one {description} file.",
      "i" = "Found {length(matches)} files matching {.code {pattern}} in {.path {raw_data_dir}}.",
      "i" = "Check that the requested archives were fully extracted."
    ))
  }

  matches[[1]]
}

if (!dir_exists(raw_data_dir)) {
  cli::cli_abort(c(
    "The raw-data directory does not exist: {.path {raw_data_dir}}.",
    "i" = "Create it, download the three archives listed at the top of this script, and extract them there."
  ))
}

lowlevel_file <- find_one_file(
  "acousticbrainz-lowlevel-features-.*-lowlevel[.]csv$",
  "AcousticBrainz low-level"
)
rhythm_file <- find_one_file(
  "acousticbrainz-lowlevel-features-.*-rhythm[.]csv$",
  "AcousticBrainz rhythm"
)
tonal_file <- find_one_file(
  "acousticbrainz-lowlevel-features-.*-tonal[.]csv$",
  "AcousticBrainz tonal"
)
redirect_file <- find_one_file(
  "canonical_recording_redirect[.]csv$",
  "canonical recording redirect"
)
metadata_file <- find_one_file(
  "canonical_musicbrainz_data[.]csv$",
  "canonical MusicBrainz metadata"
)

required_redirect_columns <- c(
  "recording_mbid",
  "canonical_recording_mbid"
)

required_metadata_columns <- c(
  "artist_credit_name",
  "release_name",
  "recording_mbid",
  "recording_name",
  "score"
)

check_columns <- function(file, required_columns) {
  observed_columns <- names(read_csv(file, n_max = 0, show_col_types = FALSE))
  missing_columns <- setdiff(required_columns, observed_columns)

  if (length(missing_columns) > 0L) {
    cli::cli_abort(c(
      "Required columns are missing from {.path {file}}.",
      "x" = "Missing: {toString(missing_columns)}"
    ))
  }
}

check_columns(
  lowlevel_file,
  c(
    "mbid",
    "submission_offset",
    "average_loudness",
    "dynamic_complexity",
    "mfcc_zero_mean"
  )
)
check_columns(
  rhythm_file,
  c(
    "mbid",
    "submission_offset",
    "bpm",
    "bpm_histogram_first_peak_bpm_mean",
    "bpm_histogram_first_peak_bpm_median",
    "bpm_histogram_second_peak_bpm_mean",
    "bpm_histogram_second_peak_bpm_median",
    "danceability",
    "onset_rate"
  )
)
check_columns(
  tonal_file,
  c(
    "mbid",
    "submission_offset",
    "key_key",
    "key_scale",
    "tuning_frequency",
    "tuning_equal_tempered_deviation"
  )
)
check_columns(redirect_file, required_redirect_columns)
check_columns(metadata_file, required_metadata_columns)

if (!file_exists(artist_pool_file)) {
  cli::cli_abort(c(
    "The artist-selection file is missing: {.path {artist_pool_file}}.",
    "i" = "Supply a CSV with one column named {.field artist}."
  ))
}

artist_pool <- read_csv(
  artist_pool_file,
  col_types = cols(artist = col_character()),
  show_col_types = FALSE
) |>
  transmute(target_artist = str_squish(artist)) |>
  filter(!is.na(target_artist), target_artist != "") |>
  distinct()

# Create lazy DuckDB tables -----------------------------------------------

con <- dbConnect(duckdb())
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

sql_path <- function(file) {
  escaped_path <- str_replace_all(path_abs(file), "'", "''")
  paste0("'", escaped_path, "'")
}

dbExecute(
  con,
  str_glue(
    "CREATE VIEW acoustic_lowlevel AS
     SELECT *
     FROM read_csv_auto({sql_path(lowlevel_file)}, header = true)"
  )
)
dbExecute(
  con,
  str_glue(
    "CREATE VIEW acoustic_tonal AS
     SELECT *
     FROM read_csv_auto({sql_path(tonal_file)}, header = true)"
  )
)
dbExecute(
  con,
  str_glue(
    "CREATE VIEW acoustic_rhythm AS
     SELECT *
     FROM read_csv_auto({sql_path(rhythm_file)}, header = true)"
  )
)
dbExecute(
  con,
  str_glue(
    "CREATE VIEW recording_redirect AS
     SELECT *
     FROM read_csv_auto({sql_path(redirect_file)}, header = true)"
  )
)
dbExecute(
  con,
  str_glue(
    "CREATE VIEW canonical_metadata AS
     SELECT *
     FROM read_csv_auto({sql_path(metadata_file)}, header = true)"
  )
)

copy_to(
  con,
  artist_pool,
  name = "target_artists",
  temporary = TRUE,
  overwrite = TRUE
)

# Filter the large metadata file before joining it to the acoustic files.
# ROW_NUMBER retains the highest-priority metadata row if a recording appears
# more than once in the canonical metadata file.
dbExecute(
  con,
  "CREATE TEMP TABLE selected_metadata AS
   SELECT
     m.recording_mbid AS canonical_recording_mbid,
     m.release_mbid AS release_mbid,
     m.artist_credit_name AS artist,
     m.recording_name AS song,
     m.release_name AS release,
     a.target_artist,
     ROW_NUMBER() OVER (
       PARTITION BY m.recording_mbid
       ORDER BY TRY_CAST(m.score AS DOUBLE) DESC NULLS LAST
     ) AS metadata_rank
   FROM canonical_metadata AS m
   INNER JOIN target_artists AS a
     ON LOWER(TRIM(m.artist_credit_name)) = LOWER(TRIM(a.target_artist))"
)

selected_metadata <- tbl(con, "selected_metadata") |>
  filter(metadata_rank == 1L) |>
  select(-metadata_rank)

redirects <- tbl(con, "recording_redirect") |>
  select(recording_mbid, canonical_recording_mbid) |>
  distinct()

target_recordings <- redirects |>
  inner_join(selected_metadata, by = "canonical_recording_mbid") |>
  distinct(recording_mbid, .keep_all = TRUE)

# AcousticBrainz can contain several submissions for one recording. Keeping
# submission_offset == 0 retains the first submission for each original MBID.
lowlevel <- tbl(con, "acoustic_lowlevel") |>
  filter(submission_offset == 0L) |>
  transmute(
    recording_mbid = mbid,
    submission_offset,
    average_loudness = as.numeric(average_loudness),
    dynamic_complexity = as.numeric(dynamic_complexity),
    mfcc_zero_mean = as.numeric(mfcc_zero_mean)
  )

rhythm <- tbl(con, "acoustic_rhythm") |>
  filter(submission_offset == 0L) |>
  transmute(
    recording_mbid = mbid,
    submission_offset,
    bpm = as.numeric(bpm),
    bpm_first_peak_mean = as.numeric(bpm_histogram_first_peak_bpm_mean),
    bpm_first_peak_median = as.numeric(bpm_histogram_first_peak_bpm_median),
    bpm_second_peak_mean = as.numeric(bpm_histogram_second_peak_bpm_mean),
    bpm_second_peak_median = as.numeric(bpm_histogram_second_peak_bpm_median),
    danceability = as.numeric(danceability),
    onset_rate = as.numeric(onset_rate)
  )

tonal <- tbl(con, "acoustic_tonal") |>
  filter(submission_offset == 0L) |>
  transmute(
    recording_mbid = mbid,
    submission_offset,
    key = key_key,
    scale = key_scale,
    tuning_frequency = as.numeric(tuning_frequency),
    tuning_equal_tempered_deviation = as.numeric(
      tuning_equal_tempered_deviation
    )
  )

song_features <- target_recordings |>
  inner_join(
    lowlevel,
    by = "recording_mbid"
  ) |>
  inner_join(
    rhythm,
    by = c("recording_mbid", "submission_offset")
  ) |>
  inner_join(
    tonal,
    by = c("recording_mbid", "submission_offset")
  ) |>
  select(
    canonical_recording_mbid,
    target_artist,
    artist,
    song,
    release,
    release_mbid,
    average_loudness,
    dynamic_complexity,
    mfcc_zero_mean,
    bpm,
    bpm_first_peak_mean,
    bpm_first_peak_median,
    bpm_second_peak_mean,
    bpm_second_peak_median,
    danceability,
    onset_rate,
    key,
    scale,
    tuning_frequency,
    tuning_equal_tempered_deviation
  ) |>
  collect() |>
  mutate(
    key_number = case_match(
      key,
      "C" ~ 0,
      "C#" ~ 1,
      "Db" ~ 1,
      "D" ~ 2,
      "D#" ~ 3,
      "Eb" ~ 3,
      "E" ~ 4,
      "F" ~ 5,
      "F#" ~ 6,
      "Gb" ~ 6,
      "G" ~ 7,
      "G#" ~ 8,
      "Ab" ~ 8,
      "A" ~ 9,
      "A#" ~ 10,
      "Bb" ~ 10,
      "B" ~ 11,
      .default = NA_real_
    ),
    key_sine = sin(2 * pi * key_number / 12),
    key_cosine = cos(2 * pi * key_number / 12),
    minor_scale = as.integer(str_to_lower(scale) == "minor")
  ) |>
  filter(
    if_all(
      c(
        average_loudness,
        dynamic_complexity,
        mfcc_zero_mean,
        bpm,
        bpm_first_peak_mean,
        bpm_first_peak_median,
        bpm_second_peak_mean,
        bpm_second_peak_median,
        danceability,
        onset_rate,
        tuning_frequency,
        tuning_equal_tempered_deviation,
        key_sine,
        key_cosine,
        minor_scale
      ),
      ~ !is.na(.x) & is.finite(.x)
    )
  ) |>
  # Multiple MusicBrainz recordings can redirect to one canonical song.
  # Medians consolidate those analyses without allowing duplicates to receive
  # extra weight in k-means.
  group_by(
    canonical_recording_mbid,
    target_artist,
    release_mbid,
    artist,
    song,
    release
  ) |>
  summarise(
    key = first(key),
    scale = first(scale),
    across(
      c(
        average_loudness,
        dynamic_complexity,
        mfcc_zero_mean,
        bpm,
        bpm_first_peak_mean,
        bpm_first_peak_median,
        bpm_second_peak_mean,
        bpm_second_peak_median,
        danceability,
        onset_rate,
        tuning_frequency,
        tuning_equal_tempered_deviation,
        key_sine,
        key_cosine
      ),
      ~ median(.x, na.rm = TRUE)
    ),
    minor_scale = as.integer(mean(minor_scale, na.rm = TRUE) >= 0.5),
    n_acoustic_recordings = n(),
    .groups = "drop"
  )

if (nrow(song_features) == 0L) {
  cli::cli_abort(
    "No complete songs remained after merging. Check the source files and artist list."
  )
}

# Identify artists with at least one complete matched song.
selected_artists <- song_features |>
  distinct(target_artist)

unmatched_artists <- artist_pool |>
  anti_join(selected_artists, by = "target_artist")

if (nrow(unmatched_artists) > 0L) {
  cli::cli_warn(c(
    "{nrow(unmatched_artists)} selected artists had no complete matched songs.",
    "i" = "The unmatched artists are listed below."
  ))

  print(unmatched_artists, n = 200)
}

set.seed(song_seed)

acoustic_brainz <- song_features |>
  semi_join(selected_artists, by = "target_artist") |>
  group_by(target_artist) |>
  slice_sample(n = max_songs_per_artist) |>
  ungroup() |>
  arrange(target_artist, artist, song) |>
  rename(recording_mbid = canonical_recording_mbid)

# Diagnostics -------------------------------------------------------------

artist_counts <- acoustic_brainz |>
  count(target_artist, name = "n_songs") |>
  arrange(n_songs, target_artist)

print(artist_counts, n = Inf)

# Save the cleaned data ---------------------------------------------------

usethis::use_data(acoustic_brainz, overwrite = TRUE)
