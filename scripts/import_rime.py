#!/usr/bin/env python3
"""Converts a Rime dictionary (word<TAB>code[<TAB>weight…]) into 末笔's table: `code word [weight] …`.

Usage: import_rime.py vendor/rime-wubi/wubi86.dict.yaml Resources/wubi86.txt
"""
import re
import sys

src, dst = sys.argv[1], sys.argv[2]
entries = {}
in_body = False
with open(src, encoding="utf-8") as f:
    for n, line in enumerate(f):
        line = line.rstrip("\n")
        if not in_body:
            in_body = line == "..."
            continue
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 2 or not re.fullmatch(r"[a-z]{1,4}", parts[1]) or parts[0].startswith("$"):
            continue
        weight = int(parts[2]) if len(parts) > 2 and parts[2].isdigit() else 0
        entries.setdefault(parts[1], []).append((-weight, n, parts[0]))

with open(dst, "w", encoding="utf-8") as out:
    out.write("# 五笔 86 码表，由 rime-wubi 的 wubi86.dict.yaml 转换而来（LGPL-3.0）。\n")
    out.write("# 来源与许可证见 vendor/rime-wubi/；同一编码内按词频从高到低排列，词后面的数字是词频。\n")
    for code in sorted(entries):
        words = []
        tokens = []
        for weight, _, word in sorted(entries[code]):
            if word not in words:
                words.append(word)
                tokens.append(f"{word} {-weight}" if weight else word)
        out.write(code + " " + " ".join(tokens) + "\n")
print(f"{sum(len(v) for v in entries.values())} entries, {len(entries)} codes -> {dst}")
