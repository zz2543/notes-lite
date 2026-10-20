import { resolve } from "node:path";
import react from "@vitejs/plugin-react";
import { defineConfig } from "electron-vite";

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
  renderer: { plugins: [react()], build: { minify: true } },
});
