// The web app's half of the real-flow test (run by run.sh), in a real browser against the web
// app the real server image serves.
//
//   node web.mjs setup <server> <username> <password>
//       Creates the first admin through the web app's first-run form.
//   node web.mjs check <server> <username> <password> <result.json>
//       Signs in through the login page and opens the episode the phone saved a position on;
//       the page must show that position.

import { readFileSync } from "node:fs";
import { chromium } from "playwright";

const [mode, server, username, password, resultFile] = process.argv.slice(2);
const hms = (s) => [Math.floor(s / 3600), Math.floor((s % 3600) / 60), s % 60].map((n) => String(n).padStart(2, "0")).join(":");

const browser = await chromium.launch();
const page = await browser.newPage();
page.on("pageerror", (e) => console.log("page error:", e.message));
const shot = async (name) => page.screenshot({ path: `real-flow-${name}.png`, fullPage: true }).catch(() => {});

try {
  await page.goto(server);
  if (mode === "setup") {
    // A new server asks for its first admin.
    // The first-run form sits over the login form; both have a "username" field.
    const form = page.locator("form", { has: page.locator("#fullname") });
    await form.locator("#fullname").fill("Real Flow");
    await form.locator("#username").fill(username);
    await form.locator("#email").fill("real-flow@example.invalid");
    await form.locator("#password").fill(password);
    await form.locator('button[type="submit"]').click();
    // The form closes once the server has created the account.
    await form.waitFor({ state: "detached", timeout: 30000 });
    console.log("web: first admin created through the first-run form");
  } else if (mode === "check") {
    const result = JSON.parse(readFileSync(resultFile, "utf8"));
    const login = page.locator("form", { has: page.locator("#current-password") });
    await login.locator("#username").fill(username);
    await login.locator("#current-password").fill(password);
    await page.locator("#current-password").press("Enter");
    // The first sign-in asks for language, time zone and formats once.
    const firstRun = page.locator("#time_zone");
    const home = page.locator(".main-container");
    await Promise.race([firstRun.waitFor({ timeout: 30000 }), home.waitFor({ timeout: 30000 })]);
    if (await firstRun.isVisible()) {
      await firstRun.locator("xpath=ancestor::form").locator('button[type="submit"]').click();
      await home.waitFor({ timeout: 30000 });
    }
    console.log("web: signed in");

    await page.goto(`${server}/episode?episode_id=${result.episode_id}`);
    await page.getByText(result.episode_title, { exact: false }).first().waitFor({ timeout: 30000 });
    const shown = hms(result.position);
    await page.getByText(shown, { exact: true }).first().waitFor({ timeout: 15000 });
    console.log(`web: the episode page shows the phone's position (${shown}) for "${result.episode_title}"`);
  } else {
    throw new Error(`unknown mode ${mode}`);
  }
} catch (e) {
  await shot(mode);
  console.error(`web ${mode} failed: ${e.message}`);
  process.exitCode = 1;
} finally {
  await browser.close();
}
