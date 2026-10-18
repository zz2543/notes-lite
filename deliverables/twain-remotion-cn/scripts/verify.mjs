import { readFileSync, existsSync, mkdirSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { execFileSync } from "node:child_process";
import { bundle } from "@remotion/bundler";
import { getCompositions, renderStill } from "@remotion/renderer";

const root = resolve(import.meta.dirname, "..");
const timing = JSON.parse(readFileSync(resolve(root, "src/timing.json")));
const ids = Object.keys(timing);
let frame = 0;
const checkpoints = [];
for (const id of ids) {
  const scene = timing[id];
  if (scene.clips.length !== 2 || scene.captions.length !== 2)
    throw Error(`Missing narration: ${id}`);
  for (const clip of scene.clips) {
    const path = resolve(root, "public", clip.file);
    if (!existsSync(path)) throw Error(`Missing audio: ${clip.file}`);
    const actual = Number(
      execFileSync(
        "ffprobe",
        [
          "-v",
          "error",
          "-show_entries",
          "format=duration",
          "-of",
          "default=nw=1:nk=1",
          path,
        ],
        { encoding: "utf8" },
      ),
    );
    if (
      Math.abs(actual - clip.duration) > 0.02 ||
      clip.from + actual > scene.duration
    )
      throw Error(`Audio timing: ${clip.file}`);
  }
  checkpoints.push({ id, frame: frame + 180 });
  frame += Math.round(scene.duration * 30);
}
mkdirSync(resolve(root, "out"), { recursive: true });
const url = await bundle({
  entryPoint: resolve(root, "src/index.ts"),
  enableCaching: true,
});
const compositions = await getCompositions(url);
const composition = compositions.find((c) => c.id === "TwainPromo");
if (composition.durationInFrames !== frame)
  throw Error("Composition duration mismatch");
for (const check of checkpoints) {
  await renderStill({
    serveUrl: url,
    composition,
    output: resolve(root, `out/${check.id}.png`),
    frame: check.frame,
    imageFormat: "png",
  });
  console.log(`Verified frame: ${check.id}`);
}
writeFileSync(
  resolve(root, "verification.json"),
  JSON.stringify(
    {
      fps: 30,
      width: 1920,
      height: 1080,
      frames: frame,
      seconds: frame / 30,
      narrationClips: 16,
      checkpoints,
      status: "timing-and-stills-passed",
    },
    null,
    2,
  ),
);
