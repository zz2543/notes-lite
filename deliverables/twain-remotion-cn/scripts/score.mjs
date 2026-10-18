import { readFileSync, writeFileSync } from "node:fs";
const data = JSON.parse(
  readFileSync(new URL("../src/timing.json", import.meta.url)),
);
const seconds = Object.values(data).reduce((n, s) => n + s.duration, 0);
const rate = 48000;
const samples = Math.ceil(seconds * rate);
const wav = Buffer.alloc(44 + samples * 4);
wav.write("RIFF", 0);
wav.writeUInt32LE(wav.length - 8, 4);
wav.write("WAVEfmt ", 8);
wav.writeUInt32LE(16, 16);
wav.writeUInt16LE(1, 20);
wav.writeUInt16LE(2, 22);
wav.writeUInt32LE(rate, 24);
wav.writeUInt32LE(rate * 4, 28);
wav.writeUInt16LE(4, 32);
wav.writeUInt16LE(16, 34);
wav.write("data", 36);
wav.writeUInt32LE(samples * 4, 40);
const chords = [
  [48, 55, 60, 64],
  [45, 52, 57, 60],
  [41, 48, 53, 57],
  [43, 50, 55, 59],
];
const tone = (m) => 440 * 2 ** ((m - 69) / 12);
for (let i = 0; i < samples; i++) {
  const t = i / rate;
  const chord = chords[Math.floor(t / 8) % 4];
  const local = t % 8;
  const pad = Math.sin((Math.PI * local) / 8) ** 0.7;
  let a = 0;
  let b = 0;
  for (let k = 0; k < chord.length; k++) {
    const f = tone(chord[k]);
    a += Math.sin(2 * Math.PI * f * t) * 0.004 * pad;
    b += Math.sin(2 * Math.PI * f * 1.001 * t) * 0.004 * pad;
  }
  const pulse = t % 1.25;
  const note = tone(chord[Math.floor(t / 1.25) % 4] + 24);
  const bell = Math.sin(2 * Math.PI * note * t) * Math.exp(-pulse * 3) * 0.01;
  const fade = Math.min(1, t / 3, (seconds - t) / 4);
  wav.writeInt16LE(Math.round((a + bell) * fade * 32767), 44 + i * 4);
  wav.writeInt16LE(Math.round((b + bell) * fade * 32767), 46 + i * 4);
}
writeFileSync(new URL("../public/score.wav", import.meta.url), wav);
console.log(`Original score: ${seconds.toFixed(2)}s`);
