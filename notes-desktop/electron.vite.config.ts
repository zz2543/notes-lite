import react from "@vitejs/plugin-react";
import { defineConfig } from "electron-vite";

// Entries follow electron-vite's defaults: src/main, src/preload and src/renderer.
export default defineConfig({
  main: {},
  preload: {},
  renderer: { plugins: [react()] },
});
