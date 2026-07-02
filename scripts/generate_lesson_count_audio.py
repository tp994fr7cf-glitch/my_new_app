#!/usr/bin/env python3
"""Generate a 90-second female-voice count audio (1..90, one number per second)."""

from __future__ import annotations

import asyncio
import math
import os
import subprocess
import tempfile
from pathlib import Path

import edge_tts
from pydub import AudioSegment

VOICE = "ja-JP-NanamiNeural"
TOTAL_SECONDS = 90
SAMPLE_RATE = 44100
CHANNELS = 1
ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = ROOT / "web" / "downloads"
OUTPUT_MP3 = OUTPUT_DIR / "lesson-count-90.mp3"


def number_text(value: int) -> str:
    return str(value)


async def synthesize_number(value: int, temp_dir: Path) -> Path:
    output_path = temp_dir / f"{value:03d}.mp3"
    communicate = edge_tts.Communicate(number_text(value), VOICE)
    await communicate.save(str(output_path))
    return output_path


def fit_to_one_second(segment: AudioSegment) -> AudioSegment:
    target_ms = 1000
    segment = segment.set_frame_rate(SAMPLE_RATE).set_channels(CHANNELS)
    duration_ms = len(segment)

    if duration_ms > target_ms:
        speed = duration_ms / target_ms
        segment = _speedup(segment, speed)
        duration_ms = len(segment)

    if duration_ms > target_ms:
        segment = segment[:target_ms]

    if duration_ms < target_ms:
        silence = AudioSegment.silent(duration=target_ms - duration_ms)
        segment = segment + silence

    return segment[:target_ms]


def _speedup(segment: AudioSegment, speed: float) -> AudioSegment:
    if speed <= 1.0:
        return segment
    new_frame_rate = int(segment.frame_rate * speed)
    adjusted = segment._spawn(
        segment.raw_data,
        overrides={"frame_rate": new_frame_rate},
    )
    return adjusted.set_frame_rate(SAMPLE_RATE)


async def generate_all(temp_dir: Path) -> list[Path]:
    paths: list[Path] = []
    for value in range(1, TOTAL_SECONDS + 1):
        paths.append(await synthesize_number(value, temp_dir))
        if value % 10 == 0:
            print(f"synthesized {value}/{TOTAL_SECONDS}")
    return paths


def build_timeline(paths: list[Path]) -> AudioSegment:
    timeline = AudioSegment.silent(duration=0)
    for index, path in enumerate(paths, start=1):
        clip = AudioSegment.from_file(path)
        clip = fit_to_one_second(clip)
        timeline += clip
        if index % 10 == 0:
            print(f"aligned {index}/{TOTAL_SECONDS}")
    return timeline


def verify_duration(timeline: AudioSegment) -> None:
    expected_ms = TOTAL_SECONDS * 1000
    actual_ms = len(timeline)
    if actual_ms != expected_ms:
        raise RuntimeError(f"unexpected duration: {actual_ms}ms (expected {expected_ms}ms)")


def export_mp3(timeline: AudioSegment, output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    timeline.export(
        output_path,
        format="mp3",
        bitrate="128k",
        parameters=["-ar", str(SAMPLE_RATE), "-ac", str(CHANNELS)],
    )


async def main() -> None:
    with tempfile.TemporaryDirectory(prefix="lesson-count-audio-") as temp:
        temp_dir = Path(temp)
        paths = await generate_all(temp_dir)
        timeline = build_timeline(paths)
        verify_duration(timeline)
        export_mp3(timeline, OUTPUT_MP3)
        size_kb = math.ceil(OUTPUT_MP3.stat().st_size / 1024)
        print(f"created {OUTPUT_MP3} ({size_kb} KB, {len(timeline) / 1000:.1f}s)")


if __name__ == "__main__":
    asyncio.run(main())
