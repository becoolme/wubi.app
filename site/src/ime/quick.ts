// Slash shortcuts: `/rq` date, `/sj` time, `/dx1280` capital numerals, `/fh` symbols.
const help = 'rq 日期    sj 时间    dx 大写数字    fh 符号';
const commands = ['rq', 'sj', 'dx', 'fh'];
const two = (n: number) => String(n).padStart(2, '0');

/** Results for what follows the slash; empty when the code is incomplete or unknown. */
export function quickResults(code: string, now = new Date()): string[] {
  const [y, mo, d] = [now.getFullYear(), now.getMonth() + 1, now.getDate()];
  const [h, mi, s] = [now.getHours(), now.getMinutes(), now.getSeconds()];
  switch (code) {
    case 'rq':
      return [`${y}年${mo}月${d}日`, `${y}-${two(mo)}-${two(d)}`, `${mo}月${d}日 星期${'日一二三四五六'[now.getDay()]}`, `${y}/${two(mo)}/${two(d)}`];
    case 'sj':
      return [`${two(h)}:${two(mi)}`, `${two(h)}:${two(mi)}:${two(s)}`, `${h}点${two(mi)}分`, `${y}-${two(mo)}-${two(d)} ${two(h)}:${two(mi)}`];
    case 'fh':
      return '→ ← ↑ ↓ ★ ☆ § ℃ ¥ © ® ™ ° ± × ÷ ≠ ≤ ≥ ≈ ∞ √ ✓ ✗ • ※ № ◆ ○ ●'.split(' ');
    default: {
      if (!code.startsWith('dx')) return [];
      const capital = capitalNumber(code.slice(2));
      return capital ? [capital, capital + '元整'] : [];
    }
  }
}

/** What to show while there are no results yet; null when the code cannot become a shortcut. */
export function quickHint(code: string): string | null {
  if (code === 'dx') return '接着输入数字，如 /dx1280';
  if (code.startsWith('dx')) return null;
  return commands.some((command) => command.startsWith(code)) ? help : null;
}

export const acceptsDigits = (code: string) => code.startsWith('dx');

/** 1280 → 壹仟贰佰捌拾. Whole numbers of up to 16 digits. */
export function capitalNumber(digits: string): string | null {
  if (!/^\d{1,16}$/.test(digits)) return null;
  const numerals = '零壹贰叁肆伍陆柒捌玖';
  const small = ['仟', '佰', '拾', ''];
  const big = ['', '万', '亿', '万亿'];
  const values = [...digits.padStart(Math.ceil(digits.length / 4) * 4, '0')].map(Number);
  const groups = values.length / 4;

  let result = '';
  let skippedGroup = false;
  for (let g = 0; g < groups; g++) {
    const group = values.slice(g * 4, g * 4 + 4);
    if (group.every((v) => v === 0)) {
      skippedGroup = result !== '';
      continue;
    }
    let text = '';
    let zero = false;
    group.forEach((v, i) => {
      if (v === 0) {
        zero = true;
        return;
      }
      if (zero && !(text === '' && result === '')) text += '零';
      zero = false;
      text += numerals[v] + small[i];
    });
    if (skippedGroup && !text.startsWith('零')) text = '零' + text;
    skippedGroup = false;
    result += text + big[groups - 1 - g];
  }
  return result || '零';
}
