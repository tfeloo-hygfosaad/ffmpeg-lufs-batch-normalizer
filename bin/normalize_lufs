#!/usr/bin/env python3
import argparse, concurrent.futures, json, os, shutil, subprocess, sys
from pathlib import Path

def say(msg):
    print(msg, flush=True)

def copy_id3_critical_tags(src: Path, dst: Path):
    # Copy rating (POPM) + comment via kid3-cli. Best-effort; won't fail the whole job.
    if shutil.which("kid3-cli") is None:
        return

    # Read values from src
    rc, out, err = run([
        "kid3-cli",
        "-c", f'select "{src}"',
        "-c", "get rating",
        "-c", "get comment",
    ])
    if rc != 0:
        say(f"[WARN] tag read failed for {src}: {err.strip()}")
        return

    lines = [l.rstrip("\n") for l in out.splitlines() if l.strip() != ""]
    rating = lines[0] if len(lines) >= 1 else ""
    comment = lines[1] if len(lines) >= 2 else ""

    # Write values to dst
    rc, out2, err2 = run([
        "kid3-cli",
        "-c", f'select "{dst}"',
        "-c", f'set rating "{rating}"',
        "-c", f'set comment "{comment}"',
        "-c", "save",
    ])
    if rc != 0:
        say(f"[WARN] tag write failed for {dst}: {err2.strip()}")

def run(cmd):
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    return p.returncode, p.stdout, p.stderr

def loudnorm_pass1(infile: Path, target_i: float, target_tp: float, target_lra: float):
    # Pass 1: measure and print JSON to stderr
    cmd = [
        "ffmpeg", "-hide_banner", "-nostats", "-y",
        "-i", str(infile),
        "-ar", "48000",
        "-af", f"loudnorm=I={target_i}:TP={target_tp}:LRA={target_lra}:print_format=json",
        "-f", "null", "-"
    ]
    rc, out, err = run(cmd)
    if rc != 0:
        raise RuntimeError(err.strip() or "ffmpeg pass1 failed")

    # Extract the last JSON object from stderr
    # loudnorm prints JSON block to stderr; we find the last '{'...' }'
    start = err.rfind("{")
    end = err.rfind("}")
    if start == -1 or end == -1 or end <= start:
        raise RuntimeError("Could not parse loudnorm JSON from ffmpeg output")
    jtxt = err[start:end+1]
    data = json.loads(jtxt)
    return data

def loudnorm_pass2(infile: Path, outfile: Path, target_i: float, target_tp: float, target_lra: float, m: dict, codec: str, quality: str):
    # Ensure output dir exists
    if not outfile.parent.exists():
        outfile.parent.mkdir(parents=True, exist_ok=True)
        say(f"[DIR]  {outfile.parent}")
    tmp = outfile.with_name(outfile.stem + ".tmp" + outfile.suffix)

    # Map everything: audio + attached pictures; copy metadata; re-encode audio only
    # Notes:
    # -map 0 : include all streams (audio + cover art)
    # -c:v copy : keep cover art as-is (typically mjpeg/png)
    # -c:a ... : encode audio
    # -id3v2_version 3 : widest compatibility for MP3 tags
    # -write_id3v2 1 : ensure ID3 is written
    measured_I = m["input_i"]
    measured_TP = m["input_tp"]
    measured_LRA = m["input_lra"]
    measured_thresh = m["input_thresh"]
    offset = m["target_offset"]

    af = (
        f"loudnorm=I={target_i}:TP={target_tp}:LRA={target_lra}:"
        f"measured_I={measured_I}:measured_TP={measured_TP}:measured_LRA={measured_LRA}:"
        f"measured_thresh={measured_thresh}:offset={offset}:linear=true:print_format=summary"
    )

    cmd = [
        "ffmpeg", "-hide_banner", "-y",
        "-i", str(infile),
        "-ar", "48000",
        "-map", "0",
        "-map_metadata", "0",
        "-map_chapters", "0",
        "-c:v", "copy",
        "-af", af
    ]

    if codec == "mp3":
        # libmp3lame VBR quality: -q:a 0 is best VBR
        cmd += ["-c:a", "libmp3lame", "-q:a", quality, "-id3v2_version", "3", "-write_id3v2", "1"]
    elif codec == "flac":
        cmd += ["-c:a", "flac"]
    else:
        raise ValueError("Unsupported codec")

    cmd += [str(tmp)]

    rc, out, err = run(cmd)
    if rc != 0:
        if tmp.exists():
            tmp.unlink(missing_ok=True)
        raise RuntimeError(err.strip() or "ffmpeg pass2 failed")

    # Atomic replace
    tmp.replace(outfile)

    if codec == "mp3" and shutil.which("kid3-cli"):
        copy_id3_critical_tags(infile, outfile)

def detect_codec(path: Path):
    # Keep same extension unless user forces output codec
    ext = path.suffix.lower()
    if ext == ".mp3":
        return "mp3"
    if ext in (".flac",):
        return "flac"
    # For everything else, default to flac to avoid lossy->lossy surprises
    return "flac"

def should_skip(infile: Path, outfile: Path):
    # Skip if output exists and is newer than input
    return outfile.exists() and outfile.stat().st_mtime >= infile.stat().st_mtime

def process_one(infile: Path, in_root: Path, out_root: Path, target_i: float, target_tp: float, target_lra: float,
                out_codec: str, mp3_quality: str, force: bool):
    say(f"[START] {infile}")
    rel = infile.relative_to(in_root)
    # Preserve folder layout; choose output extension
    codec = out_codec or detect_codec(infile)
    out_ext = ".mp3" if codec == "mp3" else ".flac"
    outfile = (out_root / rel).with_suffix(out_ext)

    if not force and should_skip(infile, outfile):
        say(f"[SKIP]  {infile}")
        return ("skip", str(infile), str(outfile), "")

    m = loudnorm_pass1(infile, target_i, target_tp, target_lra)
    loudnorm_pass2(infile, outfile, target_i, target_tp, target_lra, m, codec, mp3_quality)
    say(f"[OK]    {outfile}")
    return ("ok", str(infile), str(outfile), f'I={m["input_i"]} TP={m["input_tp"]} LRA={m["input_lra"]}')

def iter_audio_files(root: Path):
    # You can add more formats if you want; mp3/flac are typical
    exts = {".mp3", ".flac", ".m4a", ".aac", ".ogg", ".opus", ".wav", ".aiff", ".alac"}
    for p in root.rglob("*"):
        if p.is_file() and p.suffix.lower() in exts:
            yield p

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("in_root", type=Path)
    ap.add_argument("out_root", type=Path)
    ap.add_argument("--i", type=float, default=-14.0, help="Target integrated loudness (LUFS)")
    ap.add_argument("--tp", type=float, default=-1.0, help="True peak ceiling (dBTP)")
    ap.add_argument("--lra", type=float, default=11.0, help="Loudness range target (LU)")
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 4) // 2))
    ap.add_argument("--out-codec", choices=["mp3", "flac"], default=None,
                    help="Force output codec. Default: keep mp3 as mp3, flac as flac, others -> flac")
    ap.add_argument("--mp3-quality", default="0", help="libmp3lame -q:a value (0 best .. 9 worst). Default 0")
    ap.add_argument("--force", action="store_true", help="Reprocess even if output exists and is newer")
    ap.add_argument("--log", default="normalize_lufs.log")
    args = ap.parse_args()

    if shutil.which("ffmpeg") is None:
        print("ffmpeg not found in PATH", file=sys.stderr)
        return 2

    in_root = args.in_root.resolve()
    out_root = args.out_root.resolve()
    out_root.mkdir(parents=True, exist_ok=True)

    files = list(iter_audio_files(in_root))
    if not files:
        print("No audio files found.", file=sys.stderr)
        return 1

    with open(args.log, "a", encoding="utf-8") as log:
        log.write(f"\n=== run in={in_root} out={out_root} I={args.i} TP={args.tp} LRA={args.lra} jobs={args.jobs} ===\n")

        ok = fail = skip = 0
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as ex:
            futs = [ex.submit(process_one, f, in_root, out_root, args.i, args.tp, args.lra,
                              args.out_codec, args.mp3_quality, args.force) for f in files]
            for fut in concurrent.futures.as_completed(futs):
                try:
                    status, src, dst, meta = fut.result()
                    if status == "ok":
                        ok += 1
                        log.write(f"OK   {src} -> {dst} [{meta}]\n")
                    else:
                        skip += 1
                        log.write(f"SKIP {src} -> {dst}\n")
                except Exception as e:
                    fail += 1
                    say(f"[FAIL]  {e}")
                    log.write(f"FAIL {e}\n")
        print(f"done: ok={ok} skip={skip} fail={fail} log={args.log}")
        return 0 if fail == 0 else 1

if __name__ == "__main__":
    raise SystemExit(main())
