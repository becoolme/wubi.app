#!/usr/bin/env python3
"""Converts a Rime dictionary (word<TAB>code[<TAB>weight…]) into 末笔's table: `code word [weight] …`.

Words the first one lacks, from word lists (--words: a word per line, maybe followed by how
often it is seen) and further Rime dictionaries (--extra), are added under the code the Wubi
rules give them from the first one's characters, so they agree with words the user makes.

Usage: import_rime.py vendor/rime-wubi/wubi86.dict.yaml Resources/wubi86.txt \
           --words data/new-words.txt --extra vendor/rime-wubi86-jidian/wubi86_jidian.dict.yaml …
"""
import argparse
import re

# Newer words come with no frequency; this puts one ahead of the rarer half of the words that
# share its code and behind the commoner half.
EXTRA_WEIGHT = 600000


def read(path):
    """(word, code, weight) for each line of a Rime dictionary's body."""
    in_body = False
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not in_body:
                in_body = line == "..."
                continue
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 2 or not re.fullmatch(r"[a-z]{1,4}", parts[1]) or parts[0].startswith("$"):
                continue
            yield parts[0], parts[1], int(parts[2]) if len(parts) > 2 and parts[2].isdigit() else 0


def read_words(path, min_count):
    """Each word of a list, leaving out those seen fewer than min_count times."""
    with open(path, encoding="utf-8") as f:
        for line in f:
            parts = line.split()
            if not parts or parts[0].startswith("#"):
                continue
            if len(parts) > 1 and parts[1].isdigit() and int(parts[1]) < min_count:
                continue
            yield parts[0]


def word_code(word, full):
    """Same as CodeTable.wordCode: two keys each of two characters; one, one and two of three;
    one each of the first three and the last of four or more."""
    if len(word) == 2:
        takes = [(0, 2), (1, 2)]
    elif len(word) == 3:
        takes = [(0, 1), (1, 1), (2, 2)]
    else:
        takes = [(0, 1), (1, 1), (2, 1), (-1, 1)]
    keys = ""
    for index, count in takes:
        code = full.get(word[index], "")
        if len(code) < count:
            return None
        keys += code[:count]
    return keys


parser = argparse.ArgumentParser()
parser.add_argument("src")
parser.add_argument("dst")
parser.add_argument("--words", action="append", default=[])
parser.add_argument("--min-count", type=int, default=0, help="for lists that say how often a word is seen")
parser.add_argument("--extra", action="append", default=[])
args = parser.parse_args()

entries = {}
known = set()
full = {}
for n, (word, code, weight) in enumerate(read(args.src)):
    entries.setdefault(code, []).append((-weight, n, word))
    known.add(word)
    if len(word) == 1 and len(code) > len(full.get(word, "")):
        full[word] = code

added = 0
sources = [read_words(path, args.min_count) for path in args.words]
sources += [(word for word, _, _ in read(path)) for path in args.extra]
for words in sources:
    for word in words:
        if word in known or len(word) < 2 or not re.fullmatch(r"[\u4e00-\u9fff]+", word):
            continue
        code = word_code(word, full)
        if code is None:
            continue
        entries.setdefault(code, []).append((-EXTRA_WEIGHT, len(known), word))
        known.add(word)
        added += 1

with open(args.dst, "w", encoding="utf-8") as out:
    out.write("# 五笔 86 码表，由 rime-wubi 的 wubi86.dict.yaml 转换而来（LGPL-3.0），\n")
    out.write("# 并补入 data/new-words.txt、rime-wubi86-jidian（Apache-2.0）和 THUOCL（MIT）里的新词。\n")
    out.write("# 来源与许可证见 vendor/。\n")
    out.write("# 同一编码内按词频从高到低排列，词后面的数字是词频。\n")
    for code in sorted(entries):
        words = []
        tokens = []
        for weight, _, word in sorted(entries[code]):
            if word not in words:
                words.append(word)
                tokens.append(f"{word} {-weight}" if weight else word)
        out.write(code + " " + " ".join(tokens) + "\n")
print(f"{sum(len(v) for v in entries.values())} entries ({added} added), {len(entries)} codes -> {args.dst}")
