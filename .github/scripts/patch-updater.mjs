/*
 * Patches upstream Vencord's standalone (HTTP) updater so it works for this fork.
 *
 * The upstream updater does:
 *   GET https://api.github.com/repos/<gitRemote>/releases/latest   -> release name holds the build hash
 *   GET https://api.github.com/repos/<gitRemote>/compare/<gitHash>...HEAD
 *
 * That `compare` call assumes the built commit exists in the same repository that
 * publishes the release. This repo only publishes *builds* of upstream Vencord, so
 * the upstream commit is not part of this repo's history and GitHub answers 404,
 * which aborts the whole update check. We already know from the release name that
 * an update exists, so we simply report one synthetic entry instead of calling
 * the compare API. Actual files are downloaded from the release assets.
 *
 * Run with the official Vencord checkout as the current working directory:
 *   node custom/.github/scripts/patch-updater.mjs
 */

import { readFileSync, writeFileSync } from "node:fs";

const FILE = "src/main/updater/http.ts";
const FIND = "async function calculateGitChanges() {";

let source;
try {
    source = readFileSync(FILE, "utf8");
} catch (err) {
    console.error(`[patch-updater] Could not read ${FILE}: ${err.message}`);
    process.exit(1);
}

const start = source.indexOf(FIND);
if (start === -1) {
    console.error(`[patch-updater] Could not find "${FIND}" in ${FILE}.`);
    console.error("[patch-updater] Upstream Vencord probably changed the updater. Update this patch.");
    process.exit(1);
}

// End of the function: the first closing brace at column 0 after the declaration.
const end = source.indexOf("\n}\n", start);
if (end === -1) {
    console.error(`[patch-updater] Could not find the end of calculateGitChanges() in ${FILE}.`);
    process.exit(1);
}

const replacement = `async function calculateGitChanges() {
    // Custom build: the upstream commit is not present in this repository's history,
    // so the GitHub compare API would 404. fetchUpdates() already decided we are
    // outdated based on the release name; surface a single entry so the UI and the
    // auto-updater proceed. The real files come from the release assets.
    const isOutdated = await fetchUpdates();
    if (!isOutdated) return [];

    return [{
        hash: "devbuild",
        author: "Vencord",
        message: "A new custom Vencord build is available"
    }];
}`;

writeFileSync(FILE, source.slice(0, start) + replacement + source.slice(end + 2));
console.log(`[patch-updater] Patched ${FILE}`);
