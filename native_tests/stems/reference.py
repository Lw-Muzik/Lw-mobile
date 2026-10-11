"""Reference separation for the host tests — the model card's pipeline, verbatim
in substance (Best-Practice/spleeter-4stems-onnx): whole-file periodic-Hann STFT
(4096/1024, front pad 3072), 512-frame splits, soft ratio masks over all four
nets, 'average' band extension, weighted overlap-add.

    python reference.py MODEL_DIR input.wav OUT_DIR [seconds]

Writes OUT_DIR/{input,vocals,drums}.wav (float32, 44.1 kHz stereo), the first
`seconds` (default 14) of the input. Needs numpy, onnxruntime, soundfile.
"""
import sys

import numpy as np
import onnxruntime as ort
import soundfile as sf

N_FFT, HOP, T, F, BINS = 4096, 1024, 512, 1024, 2049
PAD = N_FFT - HOP
W = np.hanning(N_FFT + 1)[:-1]  # periodic
STEMS = ("vocals", "drums", "bass", "other")


def stft(x):
    n = int(np.ceil((PAD + len(x)) / HOP))
    p = np.zeros((n - 1) * HOP + N_FFT)
    p[PAD:PAD + len(x)] = x
    idx = np.arange(N_FFT)[None, :] + HOP * np.arange(n)[:, None]
    return np.fft.rfft(p[idx] * W, axis=-1)


def istft(spec, length):
    frames = np.fft.irfft(spec, n=N_FFT, axis=-1)
    total = (len(spec) - 1) * HOP + N_FFT
    out, wsum = np.zeros(total), np.zeros(total)
    for i in range(len(spec)):
        at = i * HOP
        out[at:at + N_FFT] += frames[i] * W
        wsum[at:at + N_FFT] += W ** 2
    out = np.divide(out, wsum, out=np.zeros_like(out), where=wsum > 1e-8)
    return out[PAD:PAD + length]


def main():
    model_dir, wav, out_dir = sys.argv[1:4]
    seconds = float(sys.argv[4]) if len(sys.argv) > 4 else 14.0
    wave, sr = sf.read(wav, dtype="float64", always_2d=True)
    assert sr == 44100, sr
    if wave.shape[1] == 1:
        wave = np.repeat(wave, 2, axis=1)
    wave = wave[: int(seconds * sr), :2]
    n = len(wave)
    spec = np.stack([stft(wave[:, c]) for c in range(2)])
    frames = spec.shape[1]
    splits = int(np.ceil(frames / T))
    mag = np.zeros((2, splits * T, F), dtype=np.float32)
    mag[:, :frames] = np.abs(spec[:, :, :F])
    net_in = mag.reshape(2, splits, T, F)
    est = {}
    for s in STEMS:
        sess = ort.InferenceSession(f"{model_dir}/{s}.onnx", providers=["CPUExecutionProvider"])
        est[s] = sess.run(["y"], {"x": net_in})[0].reshape(2, -1, F)[:, :frames]
    denom = sum(e ** 2 for e in est.values()) + 1e-10
    out = {}
    for s in ("vocals", "drums"):
        mask = (est[s] ** 2 + 1e-10 / len(est)) / denom
        tail = np.repeat(mask.mean(axis=-1, keepdims=True), BINS - F, axis=-1)
        full = np.concatenate([mask, tail], axis=-1)
        out[s] = np.stack([istft(spec[c] * full[c], n) for c in range(2)], axis=-1)
    sf.write(f"{out_dir}/input.wav", wave.astype(np.float32), sr, subtype="FLOAT")
    for s, y in out.items():
        sf.write(f"{out_dir}/{s}.wav", y.astype(np.float32), sr, subtype="FLOAT")
    print("wrote", out_dir)


if __name__ == "__main__":
    main()
