"""Original score for the Twain feature film: soft pad, plucked arpeggio, light pulse. Writes score.wav (48 kHz stereo)."""
import numpy as np, wave, sys

SR = 48000
DUR = 68.0
BPM = 88
BEAT = 60 / BPM
N = int(SR * DUR)
L = np.zeros(N); R = np.zeros(N)
rng = np.random.default_rng(7)

def hz(m): return 440 * 2 ** ((m - 69) / 12)

# Fmaj9 – Am7 – Dm9 – Bbmaj7(#11)/C  ... two bars each
CHORDS = [
    [53, 60, 64, 67, 69, 72],   # F  (F C E G A C)
    [45, 57, 60, 64, 67, 72],   # Am7
    [50, 57, 60, 64, 65, 69],   # Dm9
    [48, 58, 62, 65, 69, 70],   # Bb/C
]
BAR = 4 * BEAT

def env(n, a, r):
    e = np.ones(n)
    ai = max(1, int(a * SR)); ri = max(1, int(r * SR))
    e[:ai] = np.linspace(0, 1, ai)
    if ri < n: e[-ri:] *= np.linspace(1, 0, ri)
    return e

def add(sig, start, pan=0.0, gain=1.0):
    i = int(start * SR)
    if i >= N: return
    sig = sig[: N - i] * gain
    L[i:i + len(sig)] += sig * np.cos((pan + 1) * np.pi / 4)
    R[i:i + len(sig)] += sig * np.sin((pan + 1) * np.pi / 4)

def pad(notes, start, length):
    n = int(length * SR); t = np.arange(n) / SR
    s = np.zeros(n)
    for m in notes:
        for det in (-0.07, 0.0, 0.08):
            f = hz(m + det)
            s += np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) + 0.18 * np.sin(4 * np.pi * f * t)
    s *= env(n, 1.2, 1.6) / (len(notes) * 3)
    return s

def pluck(m, length=1.6):
    n = int(length * SR); t = np.arange(n) / SR; f = hz(m)
    s = (np.sin(2 * np.pi * f * t) + 0.45 * np.sin(4 * np.pi * f * t) * np.exp(-t * 6) + 0.2 * np.sin(6 * np.pi * f * t) * np.exp(-t * 9))
    return s * np.exp(-t * 3.2) * env(n, 0.004, 0.2)

def kick():
    n = int(0.35 * SR); t = np.arange(n) / SR
    f = 50 + 70 * np.exp(-t * 30)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 11)

def shaker():
    n = int(0.09 * SR); t = np.arange(n) / SR
    s = rng.standard_normal(n)
    s = np.diff(np.concatenate([[0], s]))  # brighten
    return s * np.exp(-t * 55) * 0.5

def level(t):
    """Arrangement intensity over the film."""
    return np.interp(t, [0, 5, 11, 24, 40, 49, 56, 61, 64, 68], [0.0, 0.5, 0.8, 0.9, 1.0, 1.0, 0.75, 0.6, 0.5, 0.0])

bars = int(DUR / BAR) + 1
for b in range(bars):
    t0 = b * BAR
    ch = CHORDS[(b // 2) % 4] if t0 < 61 else CHORDS[0]
    # pad on every other bar, two bars long
    if b % 2 == 0:
        add(pad(ch, t0, 2 * BAR + 1.5), t0, 0.0, 0.34)
        add(pad([ch[0] - 12], t0, 2 * BAR + 1), t0, 0.0, 0.3)
    # arpeggio in eighths from ~5s
    for k in range(8):
        tt = t0 + k * BEAT / 2
        if tt < 4.8 or tt > DUR - 3: continue
        lv = level(tt)
        seq = [2, 3, 4, 5, 4, 3, 4, 5] if (b % 2) else [1, 3, 4, 5, 3, 4, 5, 3]
        m = ch[seq[k]] + 12
        add(pluck(m), tt, [-0.35, 0.35][k % 2], 0.16 * lv * (1.0 if k % 2 == 0 else 0.75))
    # pulse 24s–56s
    for k in range(4):
        tt = t0 + k * BEAT
        if 23.8 <= tt < 56:
            add(kick(), tt, 0, 0.32 * (1 if k % 2 == 0 else 0.55) * level(tt))
        if 40.2 <= tt < 56:
            add(shaker(), tt + BEAT / 2, 0.3, 0.12)
    # a bright bell on scene changes
for tt, m in [(5.0, 84), (11.2, 81), (17.4, 84), (23.8, 88), (31.4, 86), (40.2, 84), (49.4, 81), (56.0, 84), (61.4, 89)]:
    add(pluck(m, 3.0) * 0.9, tt, 0.2, 0.11)

# final chord
add(pad([41, 53, 60, 64, 67, 69, 76], 61.4, 6.6), 61.4, 0, 0.42)

mix = np.stack([L, R], 1)
# simple feedback delay for air
d = int(0.27 * SR)
wet = np.zeros_like(mix)
for i, g in enumerate([0.28, 0.16, 0.09]):
    off = d * (i + 1)
    wet[off:] += mix[:-off][:, ::(-1 if i % 2 == 0 else 1)] * g
mix = mix + wet
t = np.arange(N) / SR
mix *= np.clip(t / 1.0, 0, 1)[:, None] * np.clip((DUR - t) / 2.5, 0, 1)[:, None]
mix = np.tanh(mix * 1.1)
mix *= 0.89 / np.max(np.abs(mix))
out = sys.argv[1] if len(sys.argv) > 1 else "score.wav"
with wave.open(out, "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((mix * 32767).astype("<i2").tobytes())
print(out, f"{DUR}s")
