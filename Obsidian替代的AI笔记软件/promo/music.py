"""Soft ambient bed for the 55 s promo: pad chords, a light pluck arpeggio, chimes on the logos."""
import numpy as np
import wave

SR = 48000
DUR = 55.0
N = int(SR * DUR)
t = np.arange(N) / SR
rng = np.random.default_rng(7)


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


# Fmaj7, Em7, Dm7, Cmaj7(add9), twice, then a long Fmaj9 for the outro.
CHORDS = [[53, 57, 60, 64], [52, 55, 59, 62], [50, 53, 57, 60], [48, 52, 55, 62]] * 2 + [[53, 57, 60, 64, 67]]
SEG = 6.0
starts = [i * SEG for i in range(8)] + [48.5]
ends = starts[1:] + [DUR]

L = np.zeros(N)
R = np.zeros(N)


def env(a, b, att, rel):
    e = np.clip((t - a) / att, 0, 1) * np.clip((b + rel - t) / rel, 0, 1)
    return np.sin(e * np.pi / 2) ** 2


for ci, (a, b) in enumerate(zip(starts, ends)):
    chord = CHORDS[ci]
    e = env(a, b, 1.6, 1.8)
    for k, m in enumerate(chord):
        f = hz(m)
        for d, pan in ((-0.12, 0.3), (0.0, 0.5), (0.12, 0.7)):
            ff = f * 2 ** (d / 12 / 4)
            ph = rng.uniform(0, 2 * np.pi)
            v = np.sin(2 * np.pi * ff * t + ph) + 0.18 * np.sin(4 * np.pi * ff * t + ph)
            v *= 0.055 * e * (1 + 0.15 * np.sin(2 * np.pi * 0.2 * t + k))
            L += v * (1 - pan)
            R += v * pan
    bass = 0.11 * e * np.sin(2 * np.pi * hz(chord[0] - 12) * t)
    L += bass
    R += bass


def pluck(at, m, amp, pan, decay=0.7):
    i0 = int(at * SR)
    n = min(int(SR * 2.5), N - i0)
    if n <= 0:
        return
    tt = np.arange(n) / SR
    f = hz(m)
    v = (np.sin(2 * np.pi * f * tt) + 0.3 * np.sin(4 * np.pi * f * tt) * np.exp(-tt * 6)) * np.exp(-tt / decay)
    v *= np.clip(tt / 0.004, 0, 1) * amp
    L[i0:i0 + n] += v * (1 - pan)
    R[i0:i0 + n] += v * pan


# Arpeggio while the app is on screen (5 s to 48.5 s), 8th notes at 100 bpm.
step = 60 / 100 / 2
pattern = [0, 2, 1, 3, 2, 1, 3, 2]
x = 5.0
i = 0
while x < 48.3:
    ci = min(int(x // SEG), 7)
    chord = CHORDS[ci]
    m = chord[pattern[i % 8] % len(chord)] + 12
    ramp = min(1, (x - 5) / 3)
    pluck(x, m, 0.07 * ramp * (0.8 if i % 2 else 1), 0.35 + 0.3 * ((i * 3) % 5) / 4)
    x += step
    i += 1

# Chimes: intro logo, and the end card.
for at, notes in ((0.25, [77, 81, 84]), (1.0, [89]), (52.8, [77, 81, 84, 88]), (53.3, [89])):
    for j, m in enumerate(notes):
        pluck(at + j * 0.09, m, 0.09, 0.3 + 0.4 * j / max(1, len(notes) - 1), decay=1.4)

# Outro: sparse high notes.
for j, (at, m) in enumerate([(49.4, 72), (50.2, 76), (51.0, 79)]):
    pluck(at, m, 0.08, 0.4 + 0.1 * j, decay=1.6)

# Reverb: FFT convolution with a decaying noise tail.
irn = int(SR * 2.8)
tail = np.exp(-np.arange(irn) / SR / 0.8)
irL = rng.standard_normal(irn) * tail
irR = rng.standard_normal(irn) * tail
irL[0] = irR[0] = 0
irL /= np.sqrt((irL ** 2).sum())
irR /= np.sqrt((irR ** 2).sum())


def conv(x, ir):
    n = len(x) + len(ir)
    size = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[:len(x)]


wet = 0.35
L = L + wet * conv(L, irL)
R = R + wet * conv(R, irR)

fade = np.clip(t / 0.6, 0, 1) * np.clip((DUR - t) / 0.9, 0, 1)
L *= fade
R *= fade
peak = max(np.abs(L).max(), np.abs(R).max())
L *= 0.6 / peak
R *= 0.6 / peak

pcm = (np.stack([L, R], axis=1) * 32767).astype(np.int16)
with wave.open("music.wav", "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())
print("music.wav", DUR, "s")
