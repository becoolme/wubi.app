import type { Candidate, CodeTable } from './table';
import { acceptsDigits, quickHint, quickResults } from './quick';

export type Key =
  | { type: 'letter'; ch: string }
  | { type: 'digit'; n: number }
  /** Zero-based position on the current page. */
  | { type: 'select'; i: number }
  | { type: 'space' | 'backspace' | 'enter' | 'escape' | 'slash' | 'pageUp' | 'pageDown' | 'define' };

export interface Output {
  committed: string;
  handled: boolean;
}

const out = (committed = '', handled = true): Output => ({ committed, handled });

/**
 * One composition: the code typed so far, its candidates, and the rules for committing them.
 * The same rules as the Mac app's session, with its default settings.
 */
export class Session {
  static maxCodeLength = 4;
  static maxQuickLength = 24;

  pageSize = 5;
  buffer = '';
  page = 0;
  /** The code being given a new word, while the user types that word. */
  defining: string | null = null;
  /** The part of the new word typed so far. */
  definedWord = '';
  /** Called when a new word is saved, so it can be kept. */
  onDefine?: (code: string, word: string) => void;
  private all: Candidate[] = [];

  constructor(private table: CodeTable) {}

  get isQuick() { return this.buffer.startsWith('/'); }
  get isDefining() { return this.defining !== null; }
  get isComposing() { return this.buffer !== '' || this.defining !== null; }
  get hasCandidates() { return this.all.length > 0; }
  get pageCount() { return Math.max(1, Math.ceil(this.all.length / this.pageSize)); }
  get pageCandidates() { return this.all.slice(this.page * this.pageSize, (this.page + 1) * this.pageSize); }
  /** What shows in the text while it is still being typed. */
  get pending() { return this.definedWord + this.buffer; }

  get hint(): string | null {
    return this.all.length === 0 && this.isQuick ? quickHint(this.buffer.slice(1)) : null;
  }

  /** The code can take a word of the user's own: it matches nothing, or its last page is showing. */
  get canDefine() {
    return this.defining === null && this.buffer !== '' && !this.isQuick && this.page + 1 >= this.pageCount;
  }

  handle(key: Key): Output {
    const code = this.defining;
    if (code === null) return this.handleKey(key);
    if (this.buffer === '' && key.type !== 'letter') {
      switch (key.type) {
        case 'enter':
          return this.finishDefining(code);
        case 'escape':
          this.cancelDefining();
          break;
        case 'backspace':
          if (this.definedWord === '') {
            // Nothing typed yet: step back to the code itself.
            this.cancelDefining();
            this.setBuffer(code);
          } else {
            this.definedWord = [...this.definedWord].slice(0, -1).join('');
          }
          break;
      }
      return out();
    }
    // Whatever would have gone to the text goes into the new word instead.
    this.definedWord += this.handleKey(key).committed;
    return out();
  }

  private finishDefining(code: string): Output {
    const word = this.definedWord;
    this.cancelDefining();
    if (!word) return out();
    this.table.addUserWord(code, word);
    this.onDefine?.(code, word);
    return out(word);
  }

  private cancelDefining() {
    this.defining = null;
    this.definedWord = '';
  }

  private handleKey(key: Key): Output {
    if (key.type === 'letter') return this.type(key.ch);
    if (key.type === 'slash') {
      if (this.isComposing) return out('', false);
      this.setBuffer('/');
      return out();
    }
    if (key.type === 'define') {
      if (!this.canDefine) return out('', this.isComposing);
      this.defining = this.buffer;
      this.definedWord = '';
      this.setBuffer('');
      return out();
    }
    if (!this.isComposing) return out('', false);
    switch (key.type) {
      case 'space':
        // An unfinished shortcut is just text: keep it and let the space through.
        if (this.isQuick && this.all.length === 0) return out(this.flushLetters(), false);
        return out(this.take(0));
      case 'digit':
        if (this.isQuick && acceptsDigits(this.buffer.slice(1))) {
          if (this.buffer.length < Session.maxQuickLength) this.setBuffer(this.buffer + key.n);
          return out();
        }
        return out(key.n >= 1 && key.n <= this.pageSize ? this.take(key.n - 1) : '');
      case 'select':
        return out(this.take(key.i));
      case 'backspace':
        this.setBuffer(this.buffer.slice(0, -1));
        return out();
      case 'enter': {
        const letters = this.buffer;
        this.setBuffer('');
        return out(letters);
      }
      case 'escape':
        this.setBuffer('');
        return out();
      case 'pageDown':
        if (this.page + 1 < this.pageCount) this.page++;
        return out();
      case 'pageUp':
        if (this.page > 0) this.page--;
        return out();
    }
  }

  /** Commits the first candidate on the page (nothing if there is none) and ends the composition. */
  commitFirst(): string {
    const first = this.pageCandidates[0];
    this.setBuffer('');
    return first?.word ?? '';
  }

  /** Ends the composition and returns the raw text that was typed. */
  flushLetters(): string {
    const letters = this.pending;
    this.reset();
    return letters;
  }

  reset() {
    this.cancelDefining();
    this.setBuffer('');
  }

  private type(ch: string): Output {
    const result = out();
    if (this.isQuick) {
      if (this.buffer.length < Session.maxQuickLength) this.setBuffer(this.buffer + ch);
      return result;
    }
    if (this.buffer.length >= Session.maxCodeLength) {
      // A fifth key commits the first candidate and starts the next code.
      result.committed = this.all[0]?.word ?? '';
      this.setBuffer(ch);
    } else {
      this.setBuffer(this.buffer + ch);
    }
    if (this.buffer.length === Session.maxCodeLength && this.all.length === 1) {
      result.committed += this.all[0].word;
      this.setBuffer('');
    }
    return result;
  }

  private take(i: number): string {
    const candidate = this.pageCandidates[i];
    if (!candidate) return '';
    this.setBuffer('');
    return candidate.word;
  }

  private setBuffer(value: string) {
    this.buffer = value;
    this.page = 0;
    this.all = value.startsWith('/')
      ? quickResults(value.slice(1)).map((word) => ({ word, code: '' }))
      : this.table.candidates(value);
  }
}
