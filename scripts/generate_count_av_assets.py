#!/usr/bin/env python3
"""Generate 90-second counting audio/video test assets.

Outputs:
  - test_assets/male_count_1_to_90_90s.wav
  - test_assets/video_count_1_to_90_with_female_voice_90s.mp4
"""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = PROJECT_ROOT / "test_assets"
TMP_DIR = ASSET_DIR / ".tmp_count_voice"
MALE_DIR = TMP_DIR / "male"
FEMALE_DIR = TMP_DIR / "female"

MALE_AUDIO_OUT = ASSET_DIR / "male_count_1_to_90_90s.wav"
VIDEO_OUT = ASSET_DIR / "video_count_1_to_90_with_female_voice_90s.mp4"
FEMALE_AUDIO_TMP = TMP_DIR / "female_count_1_to_90_90s.wav"

SAMPLE_RATE = 16000
DURATION_SECONDS = 90
SPEAK_OFFSET_SECONDS = 0.15  # Keep t=0 silent, then start each count near each second.


def run(cmd: list[str]) -> None:
    """Run command and fail fast with clear output."""
    print(f"+ {' '.join(cmd)}")
    result = subprocess.run(cmd, text=True, capture_output=True)
    if result.returncode != 0:
        if result.stdout:
            print(result.stdout)
        if result.stderr:
            print(result.stderr, file=sys.stderr)
        raise RuntimeError(f"Command failed: {' '.join(cmd)}")


def ffmpeg_cmd(*args: str) -> list[str]:
    return ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", *args]


def generate_number_clips() -> None:
    MALE_DIR.mkdir(parents=True, exist_ok=True)
    FEMALE_DIR.mkdir(parents=True, exist_ok=True)

    for n in range(1, DURATION_SECONDS + 1):
        text = str(n)
        run(
            ffmpeg_cmd(
                "-f",
                "lavfi",
                "-i",
                f"flite=text='{text}':voice=kal",
                "-ar",
                str(SAMPLE_RATE),
                "-ac",
                "1",
                str(MALE_DIR / f"{n:02d}.wav"),
            )
        )
        run(
            ffmpeg_cmd(
                "-f",
                "lavfi",
                "-i",
                f"flite=text='{text}':voice=slt",
                "-ar",
                str(SAMPLE_RATE),
                "-ac",
                "1",
                str(FEMALE_DIR / f"{n:02d}.wav"),
            )
        )


def build_mix_filter(count: int) -> str:
    lines: list[str] = ["[0:a]anull[base]"]
    mix_inputs = ["[base]"]

    for i in range(1, count + 1):
        delay_ms = int(((i - 1) + SPEAK_OFFSET_SECONDS) * 1000)
        lines.append(
            f"[{i}:a]adelay={delay_ms}|{delay_ms},volume=1.0[a{i}]"
        )
        mix_inputs.append(f"[a{i}]")

    lines.append(
        "".join(mix_inputs)
        + f"amix=inputs={count + 1}:dropout_transition=0:normalize=0,"
        + "alimiter=limit=0.95[aout]"
    )
    return ";".join(lines)


def render_timeline_audio(source_dir: Path, output_path: Path) -> None:
    cmd: list[str] = ffmpeg_cmd(
        "-f",
        "lavfi",
        "-i",
        f"anullsrc=r={SAMPLE_RATE}:cl=mono:d={DURATION_SECONDS}",
    )

    for n in range(1, DURATION_SECONDS + 1):
        cmd.extend(["-i", str(source_dir / f"{n:02d}.wav")])

    filter_complex = build_mix_filter(DURATION_SECONDS)
    cmd.extend(
        [
            "-filter_complex",
            filter_complex,
            "-map",
            "[aout]",
            "-ar",
            str(SAMPLE_RATE),
            "-ac",
            "1",
            "-t",
            str(DURATION_SECONDS),
            str(output_path),
        ]
    )
    run(cmd)


def render_video_with_female_voice() -> None:
    font = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
    draw_count = (
        "drawtext="
        f"fontfile={font}:"
        "text='%{eif\\:clip(floor(t)+1\\,1\\,90)\\:d}':"
        "fontcolor=white:fontsize=120:"
        "x=(w-text_w)/2:y=(h-text_h)/2"
    )
    draw_hint = (
        "drawtext="
        f"fontfile={font}:"
        "text='seconds':"
        "fontcolor=white:fontsize=24:"
        "x=(w-text_w)/2:y=h-40"
    )

    run(
        ffmpeg_cmd(
            "-f",
            "lavfi",
            "-i",
            f"color=c=black:s=320x240:r=10:d={DURATION_SECONDS}",
            "-i",
            str(FEMALE_AUDIO_TMP),
            "-vf",
            f"{draw_count},{draw_hint}",
            "-c:v",
            "libx264",
            "-preset",
            "veryfast",
            "-crf",
            "35",
            "-pix_fmt",
            "yuv420p",
            "-c:a",
            "aac",
            "-b:a",
            "96k",
            "-t",
            str(DURATION_SECONDS),
            str(VIDEO_OUT),
        )
    )


def main() -> None:
    if shutil.which("ffmpeg") is None:
        raise RuntimeError("ffmpeg is required but was not found in PATH.")

    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    if TMP_DIR.exists():
        shutil.rmtree(TMP_DIR)
    TMP_DIR.mkdir(parents=True, exist_ok=True)

    try:
        print("Generating number clips (male/female)...")
        generate_number_clips()

        print("Building 90-second male counting audio...")
        render_timeline_audio(MALE_DIR, MALE_AUDIO_OUT)

        print("Building 90-second female counting audio for video...")
        render_timeline_audio(FEMALE_DIR, FEMALE_AUDIO_TMP)

        print("Building low-quality 90-second video with female voice...")
        render_video_with_female_voice()
    finally:
        shutil.rmtree(TMP_DIR, ignore_errors=True)

    print("Done.")
    print(f"Audio: {MALE_AUDIO_OUT}")
    print(f"Video: {VIDEO_OUT}")


if __name__ == "__main__":
    main()
