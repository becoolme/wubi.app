export interface Candidate {
  word: string;
  code: string;
}

interface Entry {
  word: string;
  weight: number;
}

const isNumber = (s: string) => /^\d+$/.test(s);

/** A Wubi code table: plain text, one line per code, `code word [weight] [word [weight]…]`. */
export class CodeTable {
  private exact = new Map<string, Entry[]>();
  private codes: string[] = [];
  count = 0;

  constructor(text: string) {
    for (const line of text.split('\n')) {
      if (!line || line.startsWith('#')) continue;
      const parts = line.split(' ');
      const entries: Entry[] = [];
      for (let i = 1; i < parts.length; i++) {
        if (isNumber(parts[i])) continue;
        const next = parts[i + 1];
        entries.push({ word: parts[i], weight: next && isNumber(next) ? Number(next) : 0 });
      }
      if (entries.length) {
        this.exact.set(parts[0], entries);
        this.count += entries.length;
      }
    }
    this.codes = [...this.exact.keys()].sort();
  }

  /** A word of the user's own comes first under its code. */
  addUserWord(code: string, word: string) {
    const rest = (this.exact.get(code) ?? []).filter((entry) => entry.word !== word);
    if (!this.exact.has(code)) {
      this.codes.push(code);
      this.codes.sort();
    }
    this.exact.set(code, [{ word, weight: 0 }, ...rest]);
  }

  /** Exact matches in table order, then code hints: words whose code starts with `input`. */
  candidates(input: string, limit = 40): Candidate[] {
    if (!input) return [];
    const result: Candidate[] = (this.exact.get(input) ?? []).map((entry) => ({ word: entry.word, code: input }));

    let lo = 0;
    let hi = this.codes.length;
    while (lo < hi) {
      const mid = (lo + hi) >> 1;
      if (this.codes[mid] < input) lo = mid + 1;
      else hi = mid;
    }
    const hints: { word: string; code: string; weight: number }[] = [];
    for (let i = lo; i < this.codes.length && this.codes[i].startsWith(input); i++) {
      const code = this.codes[i];
      if (code === input) continue;
      for (const entry of this.exact.get(code)!) hints.push({ word: entry.word, code, weight: entry.weight });
    }
    hints.sort((a, b) => a.code.length - b.code.length || b.weight - a.weight || (a.code < b.code ? -1 : 1));

    const seen = new Set(result.map((c) => c.word));
    let added = 0;
    for (const hint of hints) {
      if (seen.has(hint.word)) continue;
      seen.add(hint.word);
      result.push({ word: hint.word, code: hint.code });
      if (++added >= limit) break;
    }
    return result;
  }
}
