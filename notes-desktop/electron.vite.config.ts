import { resolve } from "node:path";
import react from "@vitejs/plugin-react";
import { defineConfig } from "electron-vite";
import { build } from "esbuild";
import type { Plugin } from "vite";

/** The bundled fonts' CSS (the text fonts' and KaTeX's) offers WOFF and TrueType behind WOFF2 for old
 *  browsers; Chromium reads WOFF2, so the other copies stay out of the app. */
const woff2Only = (): Plugin => ({
  name: "woff2-only",
  enforce: "pre",
  transform(code, id) {
    if (!/(@fontsource|katex).*\.css$/.test(id)) return;
    return { code: code.replace(/,\s*url\([^)]*\.(woff|ttf)\)\s*format\(['"](woff|truetype)['"]\)/g, ""), map: null };
  },
});

/** Fonts stay files, never inlined as data: URLs, which the page's CSP (font-src falls back to
 *  'self') would refuse; other small assets keep Vite's default. */
const assetsInlineLimit = (file: string) => (/\.(woff2?|ttf)$/.test(file) ? false : undefined);

/** space.load("react"): React, htm and Recharts as one script for homepages, bundled from
 *  src/main/spaceKit/react.entry.js at build time and served offline as /kit/react.js. */
const spaceReact = (): Plugin => ({
  name: "space-react",
  resolveId: (id) => (id === "virtual:space-react" ? "\0virtual:space-react" : undefined),
  async load(id) {
    if (id !== "\0virtual:space-react") return;
    const entry = resolve(__dirname, "src/main/spaceKit/react.entry.js");
    this.addWatchFile(entry);
    const out = await build({
      entryPoints: [entry],
      bundle: true,
      minify: true,
      format: "iife",
      target: "chrome130",
      write: false,
      legalComments: "none",
      define: { "process.env.NODE_ENV": '"production"' },
    });
    return `export default ${JSON.stringify(out.outputFiles?.[0]?.text ?? "")};`;
  },
});

// Entries follow electron-vite's defaults (src/main, src/preload and src/renderer), plus the space
// homepage's own preload (src/preload/space.ts).
export default defineConfig({
  main: { plugins: [spaceReact()] },
  preload: {
    build: {
      rollupOptions: { input: { index: resolve(__dirname, "src/preload/index.ts"), space: resolve(__dirname, "src/preload/space.ts") } },
    },
  },
  // The page is parsed on every launch: minified, it reaches first paint sooner (ticket 07).
  renderer: { plugins: [react(), woff2Only()], build: { minify: true, assetsInlineLimit } },
});
