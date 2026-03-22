# ffmpeg-lufs-batch-normalizer

Batch LUFS normalization using FFmpeg `loudnorm` (two-pass, EBU R128 compliant) **without destroying non-standard tags**.

## Why this exists

Most loudness normalization tools:

- drop POPM (rating)
- lose comment fields
- strip custom / non-standard ID3 frames
- mishandle cover art
- partially rewrite metadata

This tool is specifically designed to preserve them.

If your library depends on ratings, smart playlists, or custom tagging workflows, this is the difference between usable and broken.

## Key Features

- Two-pass `loudnorm` (accurate integrated LUFS)
- Preserves:
  - POPM (rating)
  - comment
  - non-standard/custom ID3 frames
  - cover art
  - full metadata
  - folder structure
- Re-encodes **audio only**
- Copies all streams (`-map 0`)
- Copies metadata (`-map_metadata 0`)
- Atomic output replace (no partial files)
- Parallel processing
- Smart skip (mtime-based)
- Optional tag repair via `kid3-cli`

## Requirements

Required:

- `ffmpeg`

Optional (recommended for full rating/comment preservation):

- `kid3-cli`

Verify:

```bash
ffmpeg -version
kid3-cli -v
```

## Installation

Installing script to your bin folder:

```bash
make install
```

Removing script from it cleanly:

```bash
make uninstall
```

## Usage

Basic command with all defaults:

```bash
normalize_lufs <input_dir> [options]
```

Output dir defaults to:

```bash
<input_dir> Normalised
```

To specify output directory name:

```bash
normalize_lufs <input_dir> <output_dir> [options]
```

## Options

| Option            | Meaning                                             | Default       |
| ----------------- | --------------------------------------------------- | --------------|
| `--i`             | Target integrated loudness (LUFS)                   | -14           |
| `--tp`            | True peak ceiling (dBTP)                            | -1            |
| `--lra`           | Loudness range target (LU)                          | 11            |
| `--jobs`          | Parallel workers                                    | CPU cores - 4 |
| `--out-codec`     | Force output codec (`mp3` / `flac`)                 | mp3           |
| `--mp3-quality`   | `libmp3lame -q:a` value (0 best → 9 worst)          | 0             |
| `--skip-existing` | Skip files if output exists and is newer than input | off           |
| `--log`           | Log file path                                       | disabled      |

## Codec Behavior

Default behavior:

Output mp3

Override:

```bash
normalize_lufs in out --out-codec flac
```

## Basic Examples

Default usage:

```bash
normalize_lufs "./Evil Nine/"
```

Custom output folder name with logging:

```bash
normalize_lufs "./Evil Nine/" "./Evil Nine Fixed/" --log
```

Skip already processed files:

```bash
normalize_lufs "./Evil Nine/" --skip-existing
```

Output FLAC instead of MP3:

```bash
normalize_lufs "./Evil Nine/" --out-codec flac
```

## Example Targets

Streaming-style normalization:

```bash
normalize_lufs in out --i -14 --tp -1
```

More conservative headroom:

```bash
normalize_lufs in out --i -16 --tp -1.5
```

## Processing Details

- Two-pass measurement + correction
- Uses linear=true for predictable gain adjustment
- Re-encodes audio only
- Copies metadata
- Preserves attached pictures
- Skips files when output is newer (mtime-based)
- Uses atomic temp file replacement

## What It Does NOT Do

- No hashing for skip detection
- No ReplayGain tag writing
- No metadata editing beyond preservation
- No in-place modification (source is never touched)

## Exit Codes

- `0` → success
- `1` → failures occurred
- `2` → ffmpeg not found

## Notes

- Lossy → lossy re-encoding may degrade quality.
- Processing is CPU-bound.
- WAV/AIFF/other formats default to FLAC output unless overridden.
- Without kid3-cli, rating/comment preservation may depend on container behavior.
- Output is encoded to MP3 by default.
- All files are processed on every run unless --skip-existing is used.
- Re-encoding lossy formats (e.g. MP3 → MP3) will reduce quality.
- Audio is resampled to 48kHz.
- Cover art and metadata are preserved where possible.
