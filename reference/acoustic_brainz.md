# Music recordings and acoustic features

A dataset of songs with their acoustic features. The data combine
AcousticBrainz audio analyses with MusicBrainz canonical recording
metadata. The data was filtered to only contain a select number of
artists and only up to 25 songs per artist.

## Usage

``` r
acoustic_brainz
```

## Format

A tibble with 24 variables:

- recording_mbid:

  MusicBrainz identifier for the canonical recording. Identifies a
  particular recording rather than a musical composition in general.

- target_artist:

  Artist name.

- release_mbid:

  MusicBrainz identifier for the release metadata record.

- artist:

  Artist credit from MusicBrainz.

- song:

  Recording title from MusicBrainz.

- release:

  Release title from MusicBrainz. This is not necessarily the
  recording's first release.

- key:

  Estimated musical key, expressed as a pitch-class name such as C or
  F#. Taken from the first retained acoustic analysis within each
  canonical recording.

- scale:

  Estimated musical scale, typically major or minor. Taken from the
  first retained acoustic analysis within each canonical recording.

- average_loudness:

  Normalized loudness descriptor on a scale from 0 to 1. Higher values
  indicate less dynamic range. This is not a loudness measurement in
  decibels.

- dynamic_complexity:

  Descriptor of loudness fluctuations, based on average absolute
  deviation from estimated global loudness on the decibel scale. Higher
  values indicate greater fluctuation.

- mfcc_zero_mean:

  Mean of the zeroth mel-frequency cepstral coefficient (MFCC), as
  supplied in the AcousticBrainz feature dump. A technical descriptor
  derived from the audio spectrum.

- bpm:

  Estimated tempo in beats per minute.

- bpm_first_peak_mean:

  Source-reported mean tempo at the highest peak of the BPM histogram,
  in beats per minute.

- bpm_first_peak_median:

  Source-reported median tempo at the highest peak of the BPM histogram,
  in beats per minute.

- bpm_second_peak_mean:

  Source-reported mean tempo at the second-highest peak of the BPM
  histogram, in beats per minute.

- bpm_second_peak_median:

  Source-reported median tempo at the second-highest peak of the BPM
  histogram, in beats per minute.

- danceability:

  Algorithmic estimate of danceability. Higher values indicate greater
  estimated danceability. This is neither a probability nor a human
  rating.

- onset_rate:

  Number of detected sound onsets per second, describing how frequently
  new sound events begin.

- tuning_frequency:

  Estimated reference tuning frequency, in hertz.

- tuning_equal_tempered_deviation:

  Descriptor of deviations of spectral pitch-profile peaks from
  equal-tempered pitch positions. Higher values indicate greater
  deviation.

- n_acoustic_recordings:

  Number of retained AcousticBrainz recording analyses combined to
  create the row. Only the first submission for each original recording
  identifier is considered.

## Source

AcousticBrainz low-level, rhythm, and tonal feature dumps dated June 23,
2022: <https://acousticbrainz.org/download>

MusicBrainz Canonical Data Dumps, using
`canonical_recording_redirect.csv` and `canonical_musicbrainz_data.csv`:
<https://metabrainz.org/datasets/download>

The source acoustic data and MusicBrainz core metadata were released
under CC0. Preparation code and source-file details are provided in the
package repository's `data-raw` directory.

## Details

**Selection and matching**

Artists were selected using the preparation file `artists-to-select.csv`
found in the R package data-raw folder. MusicBrainz artist credits were
matched to this list using case-insensitive matching after trimming
leading and trailing whitespace. When multiple metadata rows were
available for a recording, the row with the highest metadata score was
retained.

Original recording identifiers were linked to canonical recording
identifiers using the MusicBrainz canonical recording redirect table.
Recordings were retained only when matching metadata and matching rows
in all three AcousticBrainz feature tables (low-level, rhythm, and
tonal) were available.

**Cleaning and aggregation**

Only AcousticBrainz submissions with `submission_offset == 0` were
retained. Analyses with missing or nonfinite values in any of the
selected numeric acoustic features were removed before aggregation.

When multiple original recordings mapped to the same canonical
recording, numeric acoustic features were combined using medians. The
character variables `key` and `scale` were taken from the first retained
analysis and are retained for descriptive interpretation.

Up to 25 canonical recordings per matched artist were randomly selected
without replacement, using seed 20260925. Artists with fewer than 25
eligible recordings contribute all eligible recordings; artists with no
eligible recordings are absent.

**Use and interpretation**

Acoustic features are algorithmic estimates rather than human
assessments. The features have not been standardized in this dataset.
Consider their different units, scales, and meanings before applying
distance-based clustering.

Identifiers, artist and release information, song titles, and
`n_acoustic_recordings` provide context or provenance and should not be
treated as acoustic clustering features. In particular,
`n_acoustic_recordings` describes how the dataset was constructed, not a
characteristic of how a song sounds.

The variables `key` and `scale` are categorical musical descriptors.
They may be used to interpret results but should not be supplied
directly to k-means, which requires numeric input.

The artist list was deliberately selected for teaching. The dataset is
not a representative sample of all music, artists, or recordings. The
date of the AcousticBrainz dump indicates when the data were compiled,
not when the music was recorded or released.

## References

Essentia music feature documentation:
<https://essentia.upf.edu/streaming_extractor_music.html>
