"""Split the multi-hit range-session recordings in audio/sequences/fairway_hits/ into
individual per-strike clips (audio/sequences/fairway_hits/split/).

The two source files are continuous takes of someone hitting several balls in a row (7 and
14 hits respectively, per their filenames) rather than isolated single-hit cues like the rest
of the pack -- GolfAudio wants one clean strike sound per swing, not a whole sequence.

Onsets are found from a short-time RMS envelope: threshold at a percentile of the envelope,
merge detections closer than 350ms (a single strike's transient can have more than one local
peak above threshold), and pick whichever percentile's onset count matches the expected hit
count from the filename. Each clip runs from ~60ms before its onset to either 550ms after it
or the start of the next clip's pre-roll, whichever comes first.

Run: python tools/split_fairway_hits.py
Requires numpy.
"""
import os
import wave

import numpy as np

SRC_DIR = os.path.join(os.path.dirname(__file__), "..", "audio", "sequences", "fairway_hits")
OUT_DIR = os.path.join(SRC_DIR, "split")

FILES = [
    ("040_seven_golf_hits_to_fairway.wav", "040_fairway_hit", 7),
    ("041_fourteen_golf_hits_to_fairway.wav", "041_fairway_hit", 14),
]


def load_wav(path):
    w = wave.open(path, "rb")
    nch, sw, fr, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
    raw = w.readframes(n)
    w.close()
    assert sw == 2, f"expected 16-bit PCM, got {sw * 8}-bit"
    data = np.frombuffer(raw, dtype=np.int16).reshape(-1, nch)
    return data, nch, sw, fr


def write_wav(path, data, nch, sw, fr):
    w = wave.open(path, "wb")
    w.setnchannels(nch)
    w.setsampwidth(sw)
    w.setframerate(fr)
    w.writeframes(data.astype(np.int16).tobytes())
    w.close()


def rms_envelope(mono, fr, win_ms=15, hop_ms=5):
    win = int(fr * win_ms / 1000)
    hop = int(fr * hop_ms / 1000)
    x = mono.astype(np.float64)
    times, vals = [], []
    for start in range(0, len(x) - win, hop):
        seg = x[start:start + win]
        vals.append(np.sqrt(np.mean(seg * seg)))
        times.append(start)
    return np.array(times), np.array(vals)


def find_onsets(times, vals, expect_count, fr, min_gap_s=0.35):
    min_gap_samples = int(fr * min_gap_s)
    best = None
    for pct in [70, 75, 80, 85, 90, 60, 65, 55, 50]:
        thresh = np.percentile(vals, pct)
        above = vals > thresh
        onsets, prev = [], False
        for i, a in enumerate(above):
            if a and not prev:
                t = times[i]
                if not onsets or t - onsets[-1] > min_gap_samples:
                    onsets.append(t)
            prev = a
        if best is None or abs(len(onsets) - expect_count) < abs(len(best) - expect_count):
            best = onsets
        if len(onsets) == expect_count:
            return onsets
    return best


def segment_bounds(onsets, total_len, fr, pre_pad_ms=60, tail_ms=550):
    pre, tail = int(fr * pre_pad_ms / 1000), int(fr * tail_ms / 1000)
    bounds = []
    for i, onset in enumerate(onsets):
        start = max(0, onset - pre)
        if i + 1 < len(onsets):
            end = min(onsets[i + 1] - pre, onset + tail)
        else:
            end = min(total_len, onset + tail)
        bounds.append((start, end))
    return bounds


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for fname, out_prefix, expect_count in FILES:
        data, nch, sw, fr = load_wav(os.path.join(SRC_DIR, fname))
        mono = data.mean(axis=1)
        times, vals = rms_envelope(mono, fr)
        onsets = find_onsets(times, vals, expect_count, fr)
        print(f"{fname}: expected {expect_count} hits, detected {len(onsets)}")
        for i, (s, e) in enumerate(segment_bounds(onsets, len(mono), fr), start=1):
            out_name = f"{out_prefix}_{i:02d}.wav"
            write_wav(os.path.join(OUT_DIR, out_name), data[s:e], nch, sw, fr)
            print(f"  -> {out_name}  {(e - s) / fr:.2f}s")


if __name__ == "__main__":
    main()
