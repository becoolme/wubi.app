// Makes the code table the playground downloads: the app's own table, without the rare
// characters outside the Basic Multilingual Plane, which browsers seldom have a font for.
import { readFileSync, writeFileSync } from 'node:fs';

const source = new URL('../../Resources/wubi86.txt', import.meta.url);
const target = new URL('../public/wubi86.txt', import.meta.url);

const lines = ['# 五笔 86 码表，来自 rime-wubi（LGPL-3.0）。'];
let words = 0;
for (const line of readFileSync(source, 'utf8').split('\n')) {
  if (!line || line.startsWith('#')) continue;
  const parts = line.split(/[ \t]+/);
  const kept = [];
  for (let i = 1; i < parts.length; i++) {
    if (/^\d+$/.test(parts[i])) continue;
    if ([...parts[i]].some((ch) => ch.codePointAt(0) > 0xffff)) continue;
    kept.push(parts[i]);
    if (/^\d+$/.test(parts[i + 1] ?? '')) kept.push(parts[i + 1]);
    words++;
  }
  if (kept.length) lines.push(`${parts[0]} ${kept.join(' ')}`);
}
writeFileSync(target, lines.join('\n') + '\n');
console.log(`wubi86.txt: ${words} words`);
