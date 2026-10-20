import react from "@vitejs/plugin-react";
import { defineConfig } from "electron-vite";

// Entries follow electron-vite's defaults: src/main, src/preload and src/renderer.
export default defineConfig({
  main: {},
  preload: {},
  // The page is parsed on every launch: minified, it reaches first paint sooner (ticket 07).
  renderer: { plugins: [react()], build: { minify: true } },
});
