#!/usr/bin/env python3
"""One-shot migration: fill_box/fill_sphere/fill_cylinder -> box/sphere/cylinder.

fill_box(x1, y1, z1, x2, y2, z2, c)   -> box(vec3(x1, y1, z1), vec3(x2, y2, z2), c)
fill_sphere(cx, cy, cz, r, c)         -> sphere(size = 2r, at = vec3(cx, cy, cz), color = c)
fill_cylinder(cx, y1, y2, cz, r, c)   -> cylinder(size = 2r, height = y2 - y1 + 1,
                                                  at = vec3(cx, min_y, cz), color = c)

Literal arguments are folded; expression arguments get parenthesised math.
Occurrences in comments are left alone. Exits non-zero if any call had an
unexpected arg count (left unmodified, reported).
"""

import re
import sys


def is_num(s):
    try:
        float(s)
        return True
    except ValueError:
        return False


def fmt_num(v):
    if v == int(v):
        return str(int(v))
    return repr(v)


def find_calls(text, name):
    """Yield (start, open_paren_idx) for non-comment occurrences of name(."""
    for m in re.finditer(r"\b" + name + r"\s*\(", text):
        line_start = text.rfind("\n", 0, m.start()) + 1
        if "#" in text[line_start : m.start()]:
            continue  # commented out
        yield m.start(), m.end() - 1


def parse_args(text, open_idx):
    """Return (args, end_idx_past_close_paren) splitting top-level commas."""
    depth = 0
    args = []
    cur = []
    i = open_idx
    while i < len(text):
        ch = text[i]
        if ch == "(":
            depth += 1
            if depth > 1:
                cur.append(ch)
        elif ch == ")":
            depth -= 1
            if depth == 0:
                args.append("".join(cur).strip())
                return args, i + 1
            cur.append(ch)
        elif ch == "," and depth == 1:
            args.append("".join(cur).strip())
            cur = []
        else:
            cur.append(ch)
        i += 1
    raise ValueError("unbalanced parens")


def size_expr(r):
    if is_num(r):
        return fmt_num(float(r) * 2)
    return f"({r}) * 2.0"


def rewrite(name, args):
    if name == "fill_box":
        if len(args) != 7:
            return None
        a = args
        return (
            f"box(vec3({a[0]}, {a[1]}, {a[2]}), "
            f"vec3({a[3]}, {a[4]}, {a[5]}), {a[6]})"
        )
    if name == "fill_sphere":
        if len(args) != 5:
            return None
        cx, cy, cz, r, col = args
        return f"sphere(size = {size_expr(r)}, at = vec3({cx}, {cy}, {cz}), color = {col})"
    if name == "fill_cylinder":
        if len(args) != 6:
            return None
        cx, y1, y2, cz, r, col = args
        if is_num(y1) and is_num(y2):
            lo = min(float(y1), float(y2))
            h = int(abs(float(y2) - float(y1))) + 1
            height = str(h)
            at_y = fmt_num(lo)
        else:
            height = f"abs(({y2}) - ({y1})) + 1"
            at_y = f"min({y1}, {y2})"
        return (
            f"cylinder(size = {size_expr(r)}, height = {height}, "
            f"at = vec3({cx}, {at_y}, {cz}), color = {col})"
        )
    return None


def migrate_file(path):
    with open(path) as f:
        text = f.read()
    failures = []
    changed = False
    for name in ("fill_box", "fill_sphere", "fill_cylinder"):
        while True:
            calls = list(find_calls(text, name))
            if not calls:
                break
            start, open_idx = calls[0]
            args, end = parse_args(text, open_idx)
            new = rewrite(name, args)
            if new is None:
                failures.append(f"{path}: {name} with {len(args)} args")
                break
            text = text[:start] + new + text[end:]
            changed = True
    if changed:
        with open(path, "w") as f:
            f.write(text)
    return changed, failures


def main():
    all_failures = []
    n = 0
    for path in sys.argv[1:]:
        changed, failures = migrate_file(path)
        all_failures.extend(failures)
        if changed:
            n += 1
    print(f"migrated {n} files")
    for f in all_failures:
        print(f"SKIPPED: {f}", file=sys.stderr)
    sys.exit(1 if all_failures else 0)


if __name__ == "__main__":
    main()
