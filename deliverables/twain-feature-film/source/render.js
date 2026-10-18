// node render.js stills 3,8,13      -> stills/t3.jpg …
// node render.js video out.mp4      -> silent H.264 via ffmpeg
const { chromium } = require("playwright-core");
const { spawn } = require("child_process");
const path = require("path"), fs = require("fs");
const EXE = process.env.HOME + "/Library/Caches/ms-playwright/chromium_headless_shell-1228/chrome-headless-shell-mac-arm64/chrome-headless-shell";
const FPS = 30;
(async () => {
  const [mode, arg] = process.argv.slice(2);
  const browser = await chromium.launch({ executablePath: EXE, args: ["--allow-file-access-from-files", "--font-render-hinting=none"] });
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  page.on("pageerror", e => console.error("PAGE ERROR", e.message));
  await page.goto("file://" + path.join(__dirname, "film.html"));
  await page.evaluate(async () => { await document.fonts.ready; await Promise.all([...document.images].map(i => i.decode())); });
  const shot = async (t, type = "png") => { await page.evaluate(t => window.render(t), t); return page.screenshot({ type, quality: type === "jpeg" ? 88 : undefined }); };
  if (mode === "stills") {
    fs.mkdirSync(path.join(__dirname, "stills"), { recursive: true });
    for (const t of arg.split(",").map(Number)) fs.writeFileSync(path.join(__dirname, "stills", `t${t}.jpg`), await shot(t, "jpeg"));
  } else {
    const dur = await page.evaluate(() => window.DURATION);
    const ff = spawn("ffmpeg", ["-y", "-f", "image2pipe", "-framerate", String(FPS), "-i", "-", "-c:v", "libx264", "-preset", "slow", "-crf", "17",
      "-pix_fmt", "yuv420p", "-movflags", "+faststart", arg], { stdio: ["pipe", "ignore", "inherit"] });
    const n = Math.round(dur * FPS), t0 = Date.now();
    for (let i = 0; i < n; i++) {
      const buf = await shot(i / FPS);
      if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once("drain", r));
      if (i % 300 === 0) console.error(`frame ${i}/${n} ${((Date.now() - t0) / 1000).toFixed(0)}s`);
    }
    ff.stdin.end(); await new Promise(r => ff.on("close", r));
  }
  await browser.close();
})();
