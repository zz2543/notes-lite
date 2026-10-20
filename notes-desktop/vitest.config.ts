import { defineConfig } from "vitest/config";

// Seam A (tests/core): the core library against real temporary libraries on disk.
// tests/unit: pure modules (shared rules, the page's models), tested as plain functions.
export default defineConfig({
  test: { include: ["tests/core/**/*.test.ts", "tests/unit/**/*.test.ts"] },
});
