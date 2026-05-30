"""VOICEVOX engine client — synthesize per utterance, concatenate to mp3.

Pipeline per utterance:
  POST /audio_query?speaker=<id>&text=<utf-8 text>  -> JSON params
  POST /synthesis?speaker=<id>  with params as JSON  -> wav bytes

We then concatenate the wav segments (with a small silence pad) and run
ffmpeg to re-encode as mp3. pydub is preferred for the concatenation but
we provide a stdlib fallback using `wave` so the pipeline still works in
minimal envs.
"""

from __future__ import annotations

import json
import logging
import shutil
import subprocess
import tempfile
import wave
from pathlib import Path
from typing import Any

from . import config as cfg
from . import http

logger = logging.getLogger(__name__)

DEFAULT_TIMEOUT = 60.0


def synthesize_script(
    script: list[dict[str, Any]],
    *,
    output_mp3: Path,
    default_speaker_id: int,
    role_speakers: dict[str, int] | None = None,
) -> dict[str, Any]:
    """Render the script to `output_mp3`. Returns {duration_seconds, size_bytes}."""
    role_speakers = role_speakers or {}
    voicevox = cfg.voicevox_url()

    with tempfile.TemporaryDirectory(prefix="daily-podcast-") as workdir:
        workdir_path = Path(workdir)
        wav_paths: list[Path] = []
        for i, utter in enumerate(script):
            text = (utter.get("text") or "").strip()
            if not text:
                continue
            speaker_id = role_speakers.get(utter.get("role") or "", default_speaker_id)
            pause_ms = int(utter.get("pause_after_ms") or 0)

            speech_wav = workdir_path / f"u{i:03d}_speech.wav"
            _synth_one(voicevox, speaker_id, text, speech_wav)
            wav_paths.append(speech_wav)

            if pause_ms > 0:
                pause_wav = workdir_path / f"u{i:03d}_pause.wav"
                _make_silence_wav(pause_wav, pause_ms, sample_rate=24000)
                wav_paths.append(pause_wav)

        combined_wav = workdir_path / "combined.wav"
        _concat_wavs(wav_paths, combined_wav)

        output_mp3.parent.mkdir(parents=True, exist_ok=True)
        _wav_to_mp3(combined_wav, output_mp3)

        # Compute duration from the wav (sample-accurate). mp3 file size is taken
        # from disk after encoding.
        duration = _wav_duration_seconds(combined_wav)
        size = output_mp3.stat().st_size
        return {"duration_seconds": int(duration), "size_bytes": size}


def _synth_one(voicevox: str, speaker_id: int, text: str, out_wav: Path) -> None:
    qurl = f"{voicevox}/audio_query"
    params_q = {"speaker": str(speaker_id), "text": text}
    try:
        # /audio_query expects POST with the params in the query string and
        # an empty body. Use http helpers minimally — VOICEVOX is local so
        # latency is negligible.
        query_body = _post(qurl, params=params_q, json_body=None)
        query_json = json.loads(query_body.decode("utf-8"))
    except Exception as exc:
        raise RuntimeError(f"VOICEVOX audio_query failed: {exc}") from exc

    surl = f"{voicevox}/synthesis"
    try:
        wav_bytes = _post(
            surl,
            params={"speaker": str(speaker_id)},
            json_body=query_json,
            accept="audio/wav",
        )
    except Exception as exc:
        raise RuntimeError(f"VOICEVOX synthesis failed: {exc}") from exc

    out_wav.write_bytes(wav_bytes)


def _post(
    url: str,
    *,
    params: dict[str, str],
    json_body: Any,
    accept: str = "application/json",
) -> bytes:
    headers = {"Accept": accept}
    try:
        import httpx

        if json_body is None:
            resp = httpx.post(url, params=params, headers=headers, timeout=DEFAULT_TIMEOUT)
        else:
            resp = httpx.post(
                url,
                params=params,
                headers={**headers, "Content-Type": "application/json"},
                content=json.dumps(json_body, ensure_ascii=False).encode("utf-8"),
                timeout=DEFAULT_TIMEOUT,
            )
        if resp.status_code >= 400:
            raise http.HttpError(resp.status_code, f"{url} -> {resp.status_code}")
        return resp.content
    except ImportError:
        from urllib import error as urlerr
        from urllib import request as urlreq
        from urllib.parse import urlencode

        full_url = f"{url}?{urlencode(params)}" if params else url
        data = (
            json.dumps(json_body, ensure_ascii=False).encode("utf-8")
            if json_body is not None
            else b""
        )
        req_headers = dict(headers)
        if json_body is not None:
            req_headers["Content-Type"] = "application/json"
        req = urlreq.Request(full_url, data=data, headers=req_headers, method="POST")
        try:
            with urlreq.urlopen(req, timeout=DEFAULT_TIMEOUT) as resp:
                return resp.read()
        except urlerr.HTTPError as exc:
            raise http.HttpError(exc.code, f"{full_url} -> {exc.code}") from exc


def _make_silence_wav(out: Path, duration_ms: int, sample_rate: int) -> None:
    n_frames = int(sample_rate * duration_ms / 1000)
    with wave.open(str(out), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sample_rate)
        w.writeframes(b"\x00\x00" * n_frames)


def _concat_wavs(inputs: list[Path], output: Path) -> None:
    """Concatenate by rewriting frames. Assumes inputs share format."""
    if not inputs:
        raise ValueError("no segments to concatenate")
    with wave.open(str(inputs[0]), "rb") as first:
        params = first.getparams()
        nframes = first.getnframes()
        frames = [first.readframes(nframes)]
    for p in inputs[1:]:
        with wave.open(str(p), "rb") as w:
            if w.getframerate() != params.framerate or w.getnchannels() != params.nchannels:
                # If a silence segment was generated at a different rate, resample
                # is overkill; convert via ffmpeg in a final pass instead.
                logger.warning(
                    "daily-podcast voicevox: segment %s rate mismatch; using ffmpeg concat fallback",
                    p,
                )
                _concat_via_ffmpeg(inputs, output)
                return
            frames.append(w.readframes(w.getnframes()))

    with wave.open(str(output), "wb") as out_w:
        out_w.setparams(params)
        for chunk in frames:
            out_w.writeframes(chunk)


def _concat_via_ffmpeg(inputs: list[Path], output: Path) -> None:
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise RuntimeError("ffmpeg not found on PATH; cannot concatenate mismatched segments")
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as f:
        for p in inputs:
            f.write(f"file '{p.absolute()}'\n")
        list_path = Path(f.name)
    try:
        subprocess.run(
            [
                ffmpeg, "-y", "-f", "concat", "-safe", "0",
                "-i", str(list_path),
                "-c", "copy", str(output),
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
    finally:
        try:
            list_path.unlink()
        except OSError:
            pass


def _wav_to_mp3(wav: Path, mp3: Path) -> None:
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise RuntimeError(
            "ffmpeg not found on PATH; install ffmpeg-headless and add it to extraPackages"
        )
    subprocess.run(
        [
            ffmpeg, "-y", "-i", str(wav),
            "-codec:a", "libmp3lame", "-qscale:a", "4",
            "-ar", "44100", "-ac", "1",
            str(mp3),
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )


def _wav_duration_seconds(wav: Path) -> float:
    with wave.open(str(wav), "rb") as w:
        return w.getnframes() / float(w.getframerate())
