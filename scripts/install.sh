#!/bin/bash
# Copies build/Mobi.app into ~/Library/Input Methods and restarts it.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -d build/Mobi.app ] || ./scripts/build.sh
dest="$HOME/Library/Input Methods"
mkdir -p "$dest"
pkill -x Mobi 2>/dev/null || true
rm -rf "$dest/Mobi.app"
cp -R build/Mobi.app "$dest/"
echo "已安装到 $dest/Mobi.app"
echo "首次安装：系统设置 → 键盘 → 文字输入 → 输入法 → 编辑… → ＋ → 简体中文 → 末笔"
