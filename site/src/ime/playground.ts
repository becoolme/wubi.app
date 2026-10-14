// Runs the input method in the page's text area: keys in, text and the candidate panel out.
import { CodeTable } from './table';
import { Session, type Key } from './session';
import { Punctuation } from './punctuation';

const storageKey = 'mobi.userWords';
const root = document.querySelector<HTMLElement>('[data-playground]')!;
const input = root.querySelector<HTMLTextAreaElement>('[data-input]')!;
const panel = root.querySelector<HTMLElement>('[data-panel]')!;
const status = root.querySelector<HTMLElement>('[data-status]')!;
const mode = root.querySelector<HTMLButtonElement>('[data-mode]')!;
const clear = root.querySelector<HTMLButtonElement>('[data-clear]')!;

let session: Session | undefined;
let punctuation = new Punctuation();
let english = false;
// Where the text still being typed sits in the textarea, and how much of it there is.
let start = 0;
let shown = 0;
let lastWasDigit = false;
let loneShift = 0;

function userWords(): [string, string][] {
  try {
    return JSON.parse(localStorage.getItem(storageKey) ?? '[]');
  } catch {
    return [];
  }
}

function saveUserWords(words: [string, string][]) {
  try {
    localStorage.setItem(storageKey, JSON.stringify(words));
  } catch {
    // Private windows may refuse; the word still works until the page is closed.
  }
  clear.hidden = words.length === 0;
}

async function load() {
  status.textContent = '正在载入码表…';
  try {
    const response = await fetch(root.dataset.table!);
    if (!response.ok) throw new Error(String(response.status));
    const table = new CodeTable(await response.text());
    const words = userWords();
    for (const [code, word] of words) table.addUserWord(code, word);
    clear.hidden = words.length === 0;
    session = new Session(table);
    session.onDefine = (code, word) => saveUserWords([...userWords().filter(([c, w]) => c !== code || w !== word), [code, word]]);
    input.disabled = false;
    status.textContent = `码表已载入，共 ${table.count.toLocaleString('zh-CN')} 个字词`;
  } catch {
    status.textContent = '码表没有载入成功，刷新页面再试一次';
  }
}

// The table is a couple of megabytes: fetch it only once the playground is near.
const observer = new IntersectionObserver((entries) => {
  if (entries.some((entry) => entry.isIntersecting)) {
    observer.disconnect();
    load();
  }
}, { rootMargin: '400px' });
observer.observe(root);

/** Puts `committed` into the text, followed by whatever is still being typed. */
function write(committed: string) {
  if (!session) return;
  const pending = session.pending;
  if (shown === 0) {
    if (!committed && !pending) return;
    start = input.selectionStart;
  }
  const end = shown === 0 ? input.selectionEnd : start + shown;
  input.setRangeText(committed + pending, start, end, 'end');
  start += committed.length;
  shown = pending.length;
}

function send(key: Key): boolean {
  const output = session!.handle(key);
  write(output.committed);
  return output.handled;
}

/** What a key that ends the composition leaves behind. */
function commitPending(): string {
  return session!.isQuick && !session!.hasCandidates ? session!.flushLetters() : session!.commitFirst();
}

/** Leaves what was typed in the text as it is and ends the composition. */
function flush() {
  session?.reset();
  shown = 0;
  render();
}

function process(event: KeyboardEvent): boolean {
  const s = session!;
  const wasDigit = lastWasDigit;
  lastWasDigit = false;
  const composing = s.isComposing;

  switch (event.key) {
    case ' ': return send({ type: 'space' });
    case 'Backspace': return send({ type: 'backspace' });
    case 'Enter': return send({ type: 'enter' });
    case 'Escape': return send({ type: 'escape' });
    case 'PageUp': return send({ type: 'pageUp' });
    case 'PageDown': return send({ type: 'pageDown' });
    case 'ArrowLeft': case 'ArrowRight': case 'ArrowUp': case 'ArrowDown': return composing;
  }
  const ch = event.key;
  if (ch.length !== 1) return composing && ch !== 'Tab' ? true : (composing && flush(), false);

  const lower = ch >= 'a' && ch <= 'z';
  const upper = ch >= 'A' && ch <= 'Z';
  const digit = ch >= '0' && ch <= '9';

  if (s.isDefining) {
    // Only keys that build the new word count; nothing reaches the text until it is saved.
    if (lower) send({ type: 'letter', ch });
    else if (digit) send({ type: 'digit', n: Number(ch) });
    else if (ch === ';') send({ type: 'select', i: 1 });
    else if (ch === "'") send({ type: 'select', i: 2 });
    else if (ch === '-') send({ type: 'pageUp' });
    else if (ch === '=') send({ type: 'pageDown' });
    return true;
  }

  if (lower) return send({ type: 'letter', ch });
  if (upper) {
    if (!composing) return false;
    write(commitPending() + ch);
    return true;
  }
  if (ch === '/' && !composing && send({ type: 'slash' })) return true;

  if (composing) {
    if (digit) return send({ type: 'digit', n: Number(ch) });
    switch (ch) {
      case ';': return send({ type: 'select', i: 1 });
      case "'": return send({ type: 'select', i: 2 });
      case '-': return send({ type: 'pageUp' });
      case '=': return send({ type: s.canDefine ? 'define' : 'pageDown' });
    }
  }
  if (digit) {
    lastWasDigit = true;
    return false;
  }
  // 3.14 keeps its ASCII point.
  if (ch === '.' && wasDigit && !composing) return false;

  const mapped = punctuation.map(ch);
  if (mapped) {
    write((composing ? commitPending() : '') + mapped);
    return true;
  }
  if (!composing) return false;
  write(commitPending() + ch);
  return true;
}

input.addEventListener('keydown', (event) => {
  if (!session) return;
  if (event.key === 'Shift') {
    loneShift = event.repeat ? 0 : event.timeStamp;
    return;
  }
  loneShift = 0;
  if (event.isComposing || event.key === 'Process' || event.keyCode === 229) {
    status.textContent = '系统输入法还开着：请先切到英文（ABC），再在这里打字';
    return;
  }
  if (event.metaKey || event.ctrlKey || event.altKey) {
    if (session.isComposing) flush();
    return;
  }
  if (english) return;
  if (process(event)) event.preventDefault();
  render();
});

input.addEventListener('keyup', (event) => {
  // A Shift pressed and let go on its own switches between Chinese and English.
  if (event.key === 'Shift' && loneShift && event.timeStamp - loneShift < 500) setEnglish(!english);
  loneShift = 0;
});

function setEnglish(value: boolean) {
  english = value;
  // Letters not yet committed stay as English text.
  flush();
  mode.textContent = english ? '英' : '中';
  mode.classList.toggle('en', english);
}

mode.addEventListener('click', () => {
  setEnglish(!english);
  input.focus();
});
clear.addEventListener('click', () => {
  saveUserWords([]);
  status.textContent = '自造词已清空，刷新页面后生效';
});
input.addEventListener('mousedown', () => session?.isComposing && flush());
input.addEventListener('blur', () => session?.isComposing && flush());
input.addEventListener('scroll', () => render());

/** Where the text being typed begins, measured with a hidden copy of the textarea. */
function caret(): { left: number; top: number; height: number } {
  const style = getComputedStyle(input);
  const mirror = document.createElement('div');
  for (const name of ['boxSizing', 'width', 'fontFamily', 'fontSize', 'fontWeight', 'lineHeight', 'letterSpacing',
    'paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft', 'borderTopWidth', 'borderRightWidth',
    'borderBottomWidth', 'borderLeftWidth', 'borderStyle', 'tabSize'] as const) {
    mirror.style[name] = style[name];
  }
  Object.assign(mirror.style, { position: 'absolute', visibility: 'hidden', top: '0', left: '0', whiteSpace: 'pre-wrap', overflowWrap: 'break-word' });
  mirror.textContent = input.value.slice(0, start);
  const mark = document.createElement('span');
  mark.textContent = input.value.slice(start, start + shown) || '​';
  mirror.append(mark);
  input.parentElement!.append(mirror);
  const place = { left: mark.offsetLeft, top: mark.offsetTop - input.scrollTop, height: mark.offsetHeight };
  mirror.remove();
  return place;
}

function element(tag: string, className: string, text = ''): HTMLElement {
  const node = document.createElement(tag);
  node.className = className;
  node.textContent = text;
  return node;
}

function render() {
  const s = session;
  if (!s || !s.isComposing) {
    panel.hidden = true;
    return;
  }
  panel.replaceChildren();
  const bar = element('div', 'pg-bar');
  bar.append(element('span', 'pg-code', s.defining !== null ? `造词 ${s.defining}${s.buffer ? '    ' + s.buffer : ''}` : s.buffer));
  if (s.hasCandidates) bar.append(element('span', '', `${s.page + 1} / ${s.pageCount}`));
  panel.append(bar);

  if (s.hasCandidates) {
    const row = element('div', 'pg-row');
    s.pageCandidates.forEach((candidate, i) => {
      const item = element('button', i === 0 ? 'pg-it on' : 'pg-it');
      (item as HTMLButtonElement).type = 'button';
      item.tabIndex = -1;
      item.append(element('i', '', String(i + 1)), candidate.word);
      const rest = candidate.code.slice(s.buffer.length);
      if (rest) item.append(element('i', '', rest));
      // Keep the focus in the textarea while a candidate is clicked.
      item.addEventListener('mousedown', (event) => {
        event.preventDefault();
        send({ type: 'select', i });
        render();
      });
      row.append(item);
    });
    panel.append(row);
  } else {
    let message: string;
    if (s.isDefining) {
      message = s.buffer ? '没有这个编码    ⌫ 修改'
        : s.definedWord ? `⏎ 保存「${s.definedWord}」    ⌫ 删字    ⎋ 取消`
        : '照常打出这个词    ⎋ 取消';
    } else {
      message = s.hint ?? (s.isQuick ? '没有这个代号    ⌫ 修改    ⏎ 上屏字符' : '没有这个编码    ⌫ 修改    ⏎ 上屏字母    = 造词');
    }
    panel.append(element('p', 'pg-msg', message));
  }

  panel.hidden = false;
  const at = caret();
  const field = input.parentElement!;
  const left = Math.max(0, Math.min(at.left, field.clientWidth - panel.offsetWidth));
  panel.style.left = `${left}px`;
  panel.style.top = `${Math.min(at.top + at.height + 6, field.clientHeight + 6)}px`;
}
