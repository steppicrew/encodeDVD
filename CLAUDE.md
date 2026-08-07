# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A set of Bash + Perl wrapper scripts around ffmpeg / MKVToolNix for re-encoding DVD and Blu-ray rips (produced by makemkv) as Matroska files. There is no build system, no test suite, no package manifest — the scripts are run directly on media files.

## Running

```bash
./encodeBD.sh <file.mkv> [extra ffmpeg options]   # Blu-ray, -crf 25
./encodeDvd.sh <file.mkv> [extra ffmpeg options]  # DVD, -crf 20
./encodeBD-denoise.sh <file.mkv>                  # encodeBD.sh + hqdn3d, for grainy sources
./encodeBD-delogo.sh <x>:<y>:<w>:<h> <file.mkv>   # encodeBD.sh + delogo, blanks a station logo
./encode3dBD.sh <file.mkv> [cropTop [cropBottom]] # MVC 3D → half-SBS
./convertAudio.sh <file.mkv>                      # only transcode non-AC3 audio, copy everything else
./createSup.pl [-l <lang>] [-f <size>] <file.srt> <movie.mkv>  # SRT → BD PGS .sup
./fixTitles.sh <any file in dir>                  # set mkv title from filename for all *.mkv in that dir
```

All encode scripts write to a `.out/` subdirectory next to the input file and never modify the input. `simpleEncode` refuses to overwrite an existing output file — delete it first to re-encode.

Every encode prints the assembled ffmpeg command and waits up to 10s (Enter starts immediately, Ctrl-C aborts) before starting — that pause is the only chance to abort a bad command line, so keep it when editing `simpleEncode`.

## Architecture

`functions.sh` is the shared library; every encode script is a thin wrapper that sources it via `realpath "$0"` and calls into it. Adding a new encode profile means adding a 4-line wrapper, not duplicating pipeline logic.

The wrappers differ only in their CRF, and the values look counter-intuitive: `encodeBD.sh` uses `-crf 25` while `encodeDvd.sh` uses `-crf 20`. That is how they have been since 2015 (`1641f48`) — do not "correct" them.

Note the argument order: a wrapper calls `simpleEncode "$@" -crf N`, so its own `-crf` lands *after* anything you pass, and x264 honours the last one. A `-crf` given on the command line is therefore silently overridden by the wrapper's. Call `simpleEncode` directly to choose a different CRF.

Wrappers resolve their own directory as ``realpath=`realpath "$0"` `` then ``dirname "$realpath"`` — always in that order, and always quoted. The scripts are invoked through symlinks in `~/dvd/`, where the inverted form (`realpath $(dirname "$0")`) yields the symlink's directory instead of the real one and the wrapper fails to find its sibling. Filenames here routinely contain spaces and umlauts, so unquoted command substitutions break too.

A wrapper that layers a filter (`encodeBD-denoise.sh`) passes it as a trailing `-vf`. `simpleEncode` extracts that value and *appends* it to the autodetected crop rather than replacing it, so cropping still happens.

**Filter order matters.** `simpleEncode` assembles the chain as `delogo, yadif, crop, <user -vf>`. `delogo` must come first because its coordinates are *source* pixels: put it after the crop and the frame shifts under it, so it blurs a band of picture while the logo may already have been cropped off. That is why there is a dedicated `-delogo <x>:<y>:<width>:<height>` option rather than passing `-vf delogo=…`, which would land in the wrong position. Any future filter that is positional in source coordinates needs the same treatment.

`simpleEncode` (functions.sh) is the whole pipeline for 2D content:

1. **Interlace detection** — ffmpeg `idet` over 1000 frames; parsed by an inline Perl one-liner comparing TFF+BFF vs Progressive+Undetermined. If interlaced, `yadif` is prepended to the filter chain.
2. **Option parsing** — the caller's `"$@"` is scanned to pull out `-vf` (its value becomes `$filter`, and both tokens are removed from the ffmpeg options) and to detect `-crf` (default `-crf 20` added if absent). This is why wrapper scripts pass `-vf` and `-crf` as ordinary trailing arguments.
3. **Crop detection** — `cropdetect` samples 1s at 15 points across the duration (10%–80%) and computes the **union** of the detected content boxes: each edge is the outermost value seen in any sample. This is the key insight — ffmpeg's `cropdetect` reports the *visible* area of the sampled frames, so a dark scene yields a small box that says nothing about where the black bars are. A sample can only ever shrink a box, never prove content is absent, so taking the outermost edge is correct by construction and more samples strictly help. Refinements:

   - Samples under half the largest sample's area are discarded before the union; near-black scenes otherwise drag an edge a few pixels into the picture.
   - Edges are rounded outwards to even numbers (libx264 needs mod-2).
   - It exits non-zero only when the result is unusable: no candidates parsed, an empty box, or a crop removing more than a third of a dimension. `simpleEncode` then aborts before encoding and tells the user to pass an explicit `-vf crop=…`.

   Any new caller must check that exit status, and must not pipe `cropdetect` directly into another command — that would report the downstream command's status and silently swallow the signal (this was the bug in `encode3dBD.sh`; it now captures the output first, then transforms it). Also appends `scale=1920:-2` when the source is wider than 1920 — callers that set their own scale filter need to strip it.

   **Station logos / overlays:** handled by a symmetry check, not by frequency. Letterbox and pillarbox bars are cut symmetrically, so opposite bars match within a pixel or two; a logo in a black bar breaks that by pushing one edge out while the opposite bar stays put. When the two bars on an axis differ by ≥16px, the larger one is mirrored onto both sides (refused if that would cut away more than a third of the frame). Measured on a real 2.03:1 film, honest letterboxing was asymmetric by ≤6px against a ~100px logo signal, so the threshold sits in a wide gap.

   This replaced an earlier frequency-based rule (a `CROP_IGNORE_OVERLAY` env var, now gone) that had to be opt-in because it could not distinguish a logo from content genuinely filling the frame in a minority of scenes — a title card got cropped away. Symmetry has no such ambiguity, since a full-frame scene is symmetric however rare it is, so the check is on by default. Don't reintroduce a frequency test for this.

   Frame dimensions come from the probe header on `cropdetect`'s own stderr; the symmetry step is skipped if they can't be parsed. Known trade-off: a source with a genuinely one-sided bar loses picture on the opposite side (announced on stderr).
4. **Encode** — `libx264`, `-preset medium -tune film`, all other streams copied (`-map 0:V:0 -map 0:a -map 0:s? -map 0:d? -map 0:t?`). Note the uppercase `V` and `-filter:V:0`: filters must target only the real video stream, otherwise attached cover art gets treated as video (see commits "Apply video filter only to video streams", "Fixed video filter"). Audio is deliberately left untouched — the `audiodetect` call is commented out on purpose because its AAC/PCM→AC3 conversion is lossy-to-lossy; run `convertAudio.sh` separately when that is actually wanted. Do not "restore" it. If the encode fails, `simpleEncode` returns without running the post-processing steps.
5. **`copyAttachments`** — ffmpeg drops MKV attachments, so they are re-added in a separate pass: `mkvmerge --identify --identification-format json` lists them, `mkvextract` dumps them to PID-prefixed temp files, then ffmpeg re-muxes with `-attach` plus `-metadata:s:t:N mimetype=/filename=`. The result replaces the output only if it is *larger* than the original.
6. **`cleanFile`** — `mkclean --remux`. mkclean does not reliably return a nonzero exit code, so success is judged by the output being non-empty and >100k; otherwise the temp file is removed, the encode is kept as-is, and `cleanFile` returns non-zero.

Filenames are always passed to ffmpeg with the `file:` protocol prefix (`"file:$inName"`) so that names containing `:` or looking like a URL are not misinterpreted. Keep doing this in new code.

### 3D path (`encode3dBD.sh`)

Separate from `simpleEncode`. It symlinks the input to an md5-of-basename name (working around Wine and non-ASCII filename issues), extracts the MVC H.264 track with `mkvextract`, pipes raw video through `wine FRIMDecode -i:mvc ... -sbs` into ffmpeg to produce a half-SBS encode, then re-muxes the new video with all non-video streams of the original. Finishes with `mkvpropedit --edit track:1 -s stereo-mode=1`. Requires wine + FRIMDecode; intermediate files are only deleted when the result exceeds a size threshold, so a crashed run can be resumed (an existing `tmp.3d.*.mkv` is reused). Crop is horizontal-only (the detected width/left are replaced with the full stream width and 0), and an ambiguous detection aborts before `mkvextract`/Wine rather than after.

Because the script `cd`s to the input file's directory early on, invoke it by absolute path — a relative `./encode3dBD.sh` breaks its own `realpath`-based `source` of `functions.sh`.

An older variant of this script built the half-SBS stream with tsMuxeR + AviSynth/avs2yuv instead of FRIMDecode; it was replaced in `aefce2d` ("changed 3D encoding due to wine update") and is recoverable from history if the Wine setup ever changes again.

### Subtitles (`createSup.pl`)

Renders each SRT cue to a PNG with ImageMagick `convert` (per-part `<b>`/`<i>` handling, stroke-based shadow), emits a BDN XML index, and converts it with `bdsup2subpp`. Font size and BDN `VideoFormat` are derived from the movie's width via ffmpeg. Frame rate is hard-coded to 24 (`$fps= 24` after parsing) — the value probed from the file is deliberately overridden. Dies if any rendered subtitle is wider than the screen, suggesting a smaller font size.

## Conventions in this codebase

- Inline Perl (`perl -e` / `perl -ne`) is the parser of choice for ffmpeg/mkvinfo output; keep `use strict; use warnings;`.
- `export LANG="C"` at the top of `functions.sh` is load-bearing — all the regexes assume English ffmpeg/mkvinfo output. `mkvinfo` is additionally called with `--ui-language en_US`.
- ffmpeg invocations are built as Bash arrays (`cmd=( ... )`) and executed as `"${cmd[@]}"`, never as a string.
- There is no `set -euo pipefail`; failures are checked explicitly at each step instead. Library functions scope their variables with `local` and signal failure with `return`, never `exit` — `functions.sh` is sourced, so an `exit` would kill the caller's shell. The one intentional global is `outName`, which `encodeDvd.sh`'s optional remux step reads after the call.
- `copyStreams.sh` is largely a comment file: it holds worked mkvpropedit recipes (channel swap, default flags, DVD aspect ratio, tsMuxeR SRT→PGS workflow). Add new recipes there rather than to a new file.
- External tools assumed on PATH: `ffmpeg`, `mkvmerge`, `mkvextract`, `mkvinfo`, `mkvpropedit`, `mkclean`, `bdsup2subpp`, ImageMagick `convert`, `perl` with `JSON`; plus `wine` + `FRIMDecode` for 3D.
