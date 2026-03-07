import fs from "node:fs";
import path from "node:path";

const SOURCE_ASSETS = path.join("src", "assets");
const DEV_PUBLIC_ASSETS = path.join("src", ".vitepress", "public", "assets");
const BUILD_PUBLIC_ASSETS = path.join("build", ".documenter", ".vitepress", "public", "assets");

function syncDir(from, to) {
  if (!fs.existsSync(from)) return;
  fs.cpSync(from, to, {recursive: true, force: true});
}

// Source-of-truth for docs gifs is src/assets.
syncDir(SOURCE_ASSETS, DEV_PUBLIC_ASSETS);

// Keep docs:dev source mirror in sync so VitePress serves the latest local gifs
// without requiring a full docs build/re-run.
if (fs.existsSync(path.join("build", ".documenter"))) {
  syncDir(DEV_PUBLIC_ASSETS, BUILD_PUBLIC_ASSETS);
}
