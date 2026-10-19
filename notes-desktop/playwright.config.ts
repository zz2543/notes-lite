import { defineConfig } from "@playwright/test";

// Seam B: the built app, driven through its window. Run `npm run build` first.
export default defineConfig({
  testDir: "tests/e2e",
  timeout: 30_000,
  workers: 1,
  reporter: process.env.CI ? [["github"], ["list"]] : "list",
});
