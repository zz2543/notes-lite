import { mkdirSync, copyFileSync, writeFileSync, existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const app = resolve(root, "../../Obsidian替代的AI笔记软件");
mkdirSync(resolve(root, "public/screens"), { recursive: true });
mkdirSync(resolve(root, "public/voice"), { recursive: true });
for (const name of [
  "editor-light",
  "editor-dark",
  "desk-light",
  "space-light",
]) {
  copyFileSync(
    resolve(app, `Twain/docs/screenshots/${name}.jpg`),
    resolve(root, `public/screens/${name}.jpg`),
  );
}
for (const [name, file] of [
  ["review", "diff.png"],
  ["slash", "slash.png"],
]) {
  copyFileSync(
    resolve(app, `promo/img/${file}`),
    resolve(root, `public/screens/${name}.png`),
  );
}
copyFileSync(
  resolve(app, "Twain/design/icon/twain-icon-1024.png"),
  resolve(root, "public/icon.png"),
);

const scenes = [
  {
    id: "Opening",
    lines: [
      "共笔，让想法有一个自己的家。",
      "从一页笔记开始，和 AI 一起，把想法做得更好。",
    ],
  },
  {
    id: "Writing",
    lines: [
      "笔记，就在你的本地文件夹里。",
      "用 Markdown 记录，实时排版，专心写下每一个想法。",
    ],
  },
  {
    id: "Agent",
    lines: [
      "让 AI，接住你的下一步。",
      "在侧栏选择 Claude Code 或 Codex，围绕当前笔记，讨论、总结和修改。",
    ],
  },
  {
    id: "Review",
    lines: [
      "每一处改动，都能看清。",
      "逐段审阅，接受合适的修改，还原不需要的内容。决定权，始终在你。",
    ],
  },
  {
    id: "Research",
    lines: [
      "把零散资料，变成有依据的思考。",
      "围绕问题整理结论和证据，保留来源，把有用的卡片收进草稿。",
    ],
  },
  {
    id: "Spaces",
    lines: [
      "同一份笔记，也可以有不同的打开方式。",
      "用空间组织日记、习惯和项目，让文字、数据和图表，在一起。",
    ],
  },
  {
    id: "Workflow",
    lines: [
      "常做的事，让工作流接手。",
      "自定义命令和自动化，再用开放接口，连接你已有的工具。",
    ],
  },
  {
    id: "Closing",
    lines: [
      "共笔。你掌舵，AI 执笔。",
      "从记录，到思考，再到行动。让每一个想法，都向前一步。",
    ],
  },
];
const metadata = {};
let timeline = 0;
const srt = [];
const stamp = (s) =>
  new Date(Math.round(s * 1000)).toISOString().slice(11, 23).replace(".", ",");
for (const scene of scenes) {
  let time = 0.8;
  const clips = [];
  const captions = [];
  for (let i = 0; i < scene.lines.length; i++) {
    const file = `voice/${scene.id}-${i}.wav`;
    const dest = resolve(root, "public", file);
    if (!existsSync(dest)) {
      const temp = resolve(root, `public/voice/${scene.id}-${i}.mp3`);
      execFileSync(
        "uvx",
        [
          "--from",
          "edge-tts",
          "edge-tts",
          "--voice",
          "zh-CN-XiaoxiaoNeural",
          "--rate=-3%",
          "--text",
          scene.lines[i],
          "--write-media",
          temp,
        ],
        { timeout: 40000 },
      );
      execFileSync("ffmpeg", [
        "-y",
        "-v",
        "error",
        "-i",
        temp,
        "-ar",
        "48000",
        "-af",
        "loudnorm=I=-16:TP=-1.5:LRA=7",
        dest,
      ]);
    }
    const seconds = Number(
      execFileSync(
        "ffprobe",
        [
          "-v",
          "error",
          "-show_entries",
          "format=duration",
          "-of",
          "default=nw=1:nk=1",
          dest,
        ],
        { encoding: "utf8" },
      ).trim(),
    );
    clips.push({ file, from: time, duration: seconds });
    captions.push({
      text: scene.lines[i],
      startMs: Math.round(time * 1000),
      endMs: Math.round((time + seconds) * 1000),
      timestampMs: null,
      confidence: null,
      pageBreakAfter: true,
    });
    srt.push(
      `${srt.length + 1}\n${stamp(timeline + time)} --> ${stamp(timeline + time + seconds)}\n${scene.lines[i]}\n`,
    );
    time += seconds + 0.35;
  }
  const duration = Math.ceil((time + 0.9) * 30) / 30;
  metadata[scene.id] = { duration, clips, captions };
  timeline += duration;
  console.log(`${scene.id}: ${duration.toFixed(2)}s`);
  writeFileSync(
    resolve(root, "src/timing.json"),
    JSON.stringify(metadata, null, 2),
  );
}
writeFileSync(resolve(root, "captions.srt"), srt.join("\n"));
writeFileSync(
  resolve(root, "narration.txt"),
  scenes.map((s) => `${s.id}\n${s.lines.join("\n")}`).join("\n\n"),
);
writeFileSync(
  resolve(root, "voice-provider.json"),
  JSON.stringify({ voice: "zh-CN-XiaoxiaoNeural", seconds: timeline }, null, 2),
);
console.log(`Total: ${timeline.toFixed(2)}s`);
