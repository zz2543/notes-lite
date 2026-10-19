import type { Page } from "@playwright/test";
import { expect, launch, test } from "./fixtures";

const windowColor = (page: Page) => page.evaluate(() => getComputedStyle(document.body).backgroundColor);

test("the window shows the system material, or the opaque fallback colour without one", async ({ scratch }) => {
  const { app, page } = await launch(scratch);
  await expect(page.getByRole("button", { name: "选择笔记库…" })).toBeVisible();

  if (process.platform === "darwin") {
    // Vibrancy shows through the whole page; only the card and the list paint over it.
    expect(await windowColor(page)).toBe("rgba(0, 0, 0, 0)");
  } else {
    // Windows keeps its framed window (and so the fallback) until it gets its own title bar.
    await page.emulateMedia({ colorScheme: "light" });
    expect(await windowColor(page)).toBe("rgb(242, 241, 245)");
    await page.emulateMedia({ colorScheme: "dark" });
    expect(await windowColor(page)).toBe("rgb(30, 30, 34)");
  }
  await app.close();
});
