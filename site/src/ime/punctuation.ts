const fixed: Record<string, string> = {
  ',': '，', '.': '。', '?': '？', '!': '！', ';': '；', ':': '：',
  '\\': '、', '(': '（', ')': '）', '<': '《', '>': '》',
  '[': '【', ']': '】', '{': '「', '}': '」',
  '^': '……', '_': '——', '$': '￥', '~': '～', '`': '·',
};

/** Maps ASCII punctuation to full-width Chinese punctuation, pairing quotes as they are typed. */
export class Punctuation {
  private doubleOpen = false;
  private singleOpen = false;

  map(ch: string): string | undefined {
    if (ch === '"') {
      this.doubleOpen = !this.doubleOpen;
      return this.doubleOpen ? '“' : '”';
    }
    if (ch === "'") {
      this.singleOpen = !this.singleOpen;
      return this.singleOpen ? '‘' : '’';
    }
    return fixed[ch];
  }
}
