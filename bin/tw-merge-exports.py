#!/usr/bin/env python3
"""Merge two diverged Taskwarrior exports into one file to import into a fresh Taskwarrior 3.

    # on each laptop, with its OLD Taskwarrior (2.6 or 3):
    task export > ~/tw-$(hostname -s).json
    # copy both files to one machine, then:
    python3 tw-merge-exports.py tw-home.json tw-work.json > tw-merged.json
    task rc.hooks=0 import tw-merged.json          # into the new, empty Taskwarrior 3

Rule: tasks are matched by UUID. When a task exists on both sides, the copy with the newer
`modified` time wins, except that annotations from both sides are kept (unioned by entry time).
A report of what was decided goes to stderr; the merged JSON goes to stdout.

Tasks changed on BOTH laptops since they diverged cannot be merged field by field (the common
ancestor is gone), so they are listed at the end: check them after the import with `task <uuid>`.
Standard library only.
"""
import json, sys

DROP = ('id', 'urgency')                      # computed fields; import recalculates them


def load(path):
    with open(path, encoding='utf-8') as f:
        text = f.read().strip()
    if text.startswith('['):
        data = json.loads(text)
    else:                                       # very old exports: one object per line
        data = [json.loads(l.rstrip(',')) for l in text.splitlines() if l.strip().startswith('{')]
    return {t['uuid']: t for t in data if 'uuid' in t}


def stamp(t):
    return t.get('modified') or t.get('end') or t.get('entry') or ''


def main(a_path, b_path):
    a, b = load(a_path), load(b_path)
    out, both_changed = [], []
    n_a = n_b = n_same = 0
    for u in sorted(set(a) | set(b)):
        ta, tb = a.get(u), b.get(u)
        if ta and not tb:
            win = ta; n_a += 1
        elif tb and not ta:
            win = tb; n_b += 1
        else:
            ca = {k: v for k, v in ta.items() if k not in DROP}
            cb = {k: v for k, v in tb.items() if k not in DROP}
            if ca == cb:
                win = ta; n_same += 1
            else:
                win, lose = (ta, tb) if stamp(ta) >= stamp(tb) else (tb, ta)
                win = dict(win)
                notes = {n.get('entry', '') + n.get('description', ''): n
                         for n in (lose.get('annotations') or []) + (win.get('annotations') or [])}
                if notes:
                    win['annotations'] = sorted(notes.values(), key=lambda n: n.get('entry', ''))
                both_changed.append((win.get('description', '?'), u, stamp(ta), stamp(tb)))
        out.append({k: v for k, v in win.items() if k not in DROP})
    json.dump(out, sys.stdout, indent=1, ensure_ascii=False)
    sys.stdout.write('\n')
    err = sys.stderr
    print(f'{len(out)} tasks: {n_same} identical, {n_a} only in {a_path}, {n_b} only in {b_path}, '
          f'{len(both_changed)} different on both (newer kept).', file=err)
    if both_changed:
        print('\nDifferent on both laptops — newer copy kept; glance at these after importing:', file=err)
        for d, u, sa, sb in both_changed:
            print(f'  {u[:8]}  {d[:60]:60}  {a_path}:{sa}  {b_path}:{sb}', file=err)


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
