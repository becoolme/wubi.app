// What the page says about the release.
const version = '0.1.5';
const repo = 'https://github.com/becoolme/wubi.app';

export const site = {
  name: '末笔',
  title: '末笔 · Mac 上的五笔输入法',
  description: '末笔是一款只为五笔写的 Mac 输入法。候选位置不乱跳，想不起编码时用拼音查，所有记录都留在你自己的电脑上。',
  domain: 'wubi.app',
  repo,
  /** The installer scripts/release.sh makes, attached to the GitHub release. */
  downloadUrl: `${repo}/releases/latest/download/Mobi-${version}.pkg`,
  releaseUrl: `${repo}/releases/tag/v${version}`,
  version,
  requires: '需要 macOS 13 或更高版本',
  downloadSize: '约 2.2 MB',
  pricing: '免费。',
  contact: 'hi@wubi.app',
  /** Plausible analytics; production sets these in .env.production. */
  analytics: {
    domain: import.meta.env.PUBLIC_PLAUSIBLE_DOMAIN,
    src: import.meta.env.PUBLIC_PLAUSIBLE_SRC,
  },
};
