// Makes DARK the site's default theme. Run after `npx quartz build`.
//
// The darkmode plugin's inline script picks the initial theme from the OS
// (prefers-color-scheme) unless the visitor has toggled explicitly
// (localStorage "theme"). There is no config option for a fixed default, so
// this patches the built JS: the OS probe is replaced with "dark". A visitor's
// own toggle still wins, and the toggle keeps working both ways.
//
// If a plugin update changes the code shape, the pattern won't match and this
// exits non-zero so publish.ps1 stops instead of silently shipping OS-default.
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const publicDir = join(dirname(fileURLToPath(import.meta.url)), "..", "public");
const pattern =
  /(?:window\.)?matchMedia\("\(prefers-color-scheme: light\)"\)\.matches\s*\?\s*"light"\s*:\s*"dark"/g;

let patched = 0;
for (const f of readdirSync(publicDir)) {
  if (!f.endsWith(".js")) continue;
  const p = join(publicDir, f);
  const t = readFileSync(p, "utf8");
  if (pattern.test(t)) {
    writeFileSync(p, t.replace(pattern, '"dark"'));
    patched++;
    console.log(`Patched dark-default into ${f}`);
  }
}

if (patched === 0) {
  console.error(
    "patch-theme-default: pattern not found in any public/*.js — darkmode plugin code changed? Dark default NOT applied.",
  );
  process.exit(1);
}
