import { resolve } from "node:path";
import react from "@vitejs/plugin-react";
import { defineConfig } from "electron-vite";
import type { Plugin } from "vite";

/** The bundled fonts' CSS offers WOFF behind WOFF2 for old browsers; Chromium reads WOFF2, so the WOFF copies stay out of the app. */
const woff2Only = (): Plugin => ({
  name: "woff2-only",
  enforce: "pre",
  transform(code, id) {
    if (!/@fontsource.*\.css$/.test(id)) return;
    return { code: code.replace(/,\s*url\([^)]*\.woff\)\s*format\(['"]woff['"]\)/g, ""), map: null };
  },
});

// Entries follow electron-vite's defaults (src/main, src/preload and src/renderer), plus the space
// homepage's own preload (src/preload/space.ts).
export default defineConfig({
  main: {},
  preload: {
    build: {
      rollupOptions: { input: { index: resolve(__dirname, "src/preload/index.ts"), space: resolve(__dirname, "src/preload/space.ts") } },
    },
  },
  // The page is parsed on every launch: minified, it reaches first paint sooner (ticket 07).
  renderer: { plugins: [react(), woff2Only()], build: { minify: true } },
});
