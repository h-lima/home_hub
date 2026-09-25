#!/usr/bin/env python3
"""Merge Timewarrior data without losing an interval.

Two uses:

  1. As a git merge driver for the ~/.timewarrior repository (installed by
     `timew-merge.py install`), so two laptops that both tracked time never produce a conflict:

         timew-merge.py driver %O %A %B %P

     Month files (data/YYYY-MM.data) are merged line by line, three-way: a line survives if either
     side has it, unless one side deleted or changed it relative to the common ancestor (so
     `timew delete`, `timew modify`, and closing an open interval all propagate). The result is sorted
     by start time. tags.data (JSON) is merged by union.

  2. Once, to repair two data folders that have already diverged (the work laptop and the home
     laptop before this setup):

         timew-merge.py dirs  ~/tw-home/data  ~/tw-work/data  ~/tw-merged/data

     Every interval from either side is kept, duplicates are dropped, and intervals that overlap
     are listed so you can look at them with `timew summary <date>` afterwards.

Standard library only.
"""
import json, os, re, shutil, subprocess, sys

LINE = re.compile(r'^inc (\d{8}T\d{6}Z)(?: - (\d{8}T\d{6}Z))?')


def read_lines(path):
    try:
        with open(path, encoding='utf-8') as f:
            return [l.rstrip('\n') for l in f if l.strip()]
    except FileNotFoundError:
        return []


def sort_key(line):
    m = LINE.match(line)
    return (m.group(1) if m else '~', line)          # unparseable lines sort last, kept


def write_lines(path, lines):
    with open(path, 'w', encoding='utf-8') as f:
        for l in sorted(set(lines), key=sort_key):
            f.write(l + '\n')


def merge3_lines(o, a, b):
    o, a, b = set(o), set(a), set(b)
    removed = (o - a) | (o - b)
    return (a | b) - removed


def read_json(path):
    try:
        with open(path, encoding='utf-8') as f:
            return json.load(f)
    except (FileNotFoundError, ValueError):
        return {}


def merge_tags(*dicts):
    out = {}
    for d in dicts:
        for tag, v in (d or {}).items():
            if tag not in out:
                out[tag] = v
            elif isinstance(v, dict) and isinstance(out[tag], dict):
                c = max(out[tag].get('count', 0) or 0, v.get('count', 0) or 0)
                out[tag] = {**out[tag], **v, 'count': c}
    return out


def overlaps(lines):
    """(line, line) pairs whose intervals overlap; an open interval runs to 'now'."""
    iv = []
    for l in lines:
        m = LINE.match(l)
        if m:
            iv.append((m.group(1), m.group(2) or '99999999T999999Z', l))
    iv.sort()
    found, end, prev = [], '', None
    for s, e, l in iv:
        if prev and s < end:
            found.append((prev, l))
        if e > end:
            end, prev = e, l
    return found


def driver(o, a, b, path):
    if os.path.basename(path) == 'tags.data':
        merged = merge_tags(read_json(a), read_json(b))
        with open(a, 'w', encoding='utf-8') as f:
            json.dump(merged, f, indent=2, sort_keys=True)
            f.write('\n')
        return 0
    lines = merge3_lines(read_lines(o), read_lines(a), read_lines(b))
    write_lines(a, lines)
    for x, y in overlaps(lines):
        print(f'timew-merge: overlapping intervals in {path}:\n  {x}\n  {y}', file=sys.stderr)
    return 0


def dirs(a, b, out):
    os.makedirs(out, exist_ok=True)
    names = sorted(set(os.listdir(a)) | set(os.listdir(b)))
    total, clashes = 0, []
    for n in names:
        pa, pb, po = os.path.join(a, n), os.path.join(b, n), os.path.join(out, n)
        if n == 'undo.data':
            continue
        if n == 'tags.data':
            with open(po, 'w', encoding='utf-8') as f:
                json.dump(merge_tags(read_json(pa), read_json(pb)), f, indent=2, sort_keys=True)
                f.write('\n')
            continue
        if not n.endswith('.data'):
            src = pa if os.path.exists(pa) else pb
            if os.path.isfile(src):
                shutil.copy2(src, po)
            continue
        la, lb = read_lines(pa), read_lines(pb)
        lines = set(la) | set(lb)
        write_lines(po, lines)
        total += len(lines)
        print(f'{n}: home {len(set(la))}, work {len(set(lb))}, merged {len(lines)}')
        clashes += overlaps(lines)
    print(f'\n{total} intervals written to {out}')
    if clashes:
        print(f'\n{len(clashes)} overlapping pair(s) — usually the same session logged on both laptops,')
        print('or a clock left running. Check each with `timew summary <day> :ids` and `timew delete @N`:')
        for x, y in clashes:
            print(f'  {x}\n  {y}\n')
    return 0


def install(repo):
    """Register the driver in <repo>/.git/config and write .gitattributes/.gitignore."""
    me = os.path.abspath(__file__)
    subprocess.run(['git', '-C', repo, 'config', 'merge.timew.name', 'Timewarrior interval merge'], check=True)
    subprocess.run(['git', '-C', repo, 'config', 'merge.timew.driver',
                    f'python3 {me} driver %O %A %B %P'], check=True)
    attrs = os.path.join(repo, '.gitattributes')
    want = ['data/*.data merge=timew']
    have = read_lines(attrs)
    with open(attrs, 'a', encoding='utf-8') as f:
        for w in want:
            if w not in have:
                f.write(w + '\n')
    ign = os.path.join(repo, '.gitignore')
    have = read_lines(ign)
    with open(ign, 'a', encoding='utf-8') as f:
        for w in ['data/undo.data', '*.lock']:
            if w not in have:
                f.write(w + '\n')
    print(f'merge driver "timew" registered in {repo}')
    return 0


if __name__ == '__main__':
    args = sys.argv[1:]
    if len(args) == 5 and args[0] == 'driver':
        sys.exit(driver(*args[1:]))
    if len(args) == 4 and args[0] == 'dirs':
        sys.exit(dirs(*args[1:]))
    if len(args) in (1, 2) and args[0] == 'install':
        default = os.environ.get('TIMEWARRIORDB') or os.path.expanduser('~/.timewarrior')
        sys.exit(install(args[1] if len(args) == 2 else default))
    print(__doc__)
    sys.exit(2)
