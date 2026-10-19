import { defineConfig } from "vitest/config";

// Seam A: the core library against real temporary libraries on disk.
export default defineConfig({
  test: { include: ["tests/core/**/*.test.ts"] },
});
