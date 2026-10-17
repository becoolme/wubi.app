// Prints what changed in one release, from site/src/changelog.ts, as the HTML Sparkle shows in
// its update window: node scripts/release-notes.mjs <version>
import { changelog } from '../site/src/changelog.ts';

const version = process.argv[2];
const release = changelog.find((r) => r.version === version);
if (!release) {
  console.error(`site/src/changelog.ts has no entry for ${version}`);
  process.exit(1);
}
const escape = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
console.log(`<ul>${release.changes.map((c) => `<li>${escape(c)}</li>`).join('')}</ul>`);
