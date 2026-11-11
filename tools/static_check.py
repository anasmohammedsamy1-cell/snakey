#!/usr/bin/env python3
"""Static sanity checks for the project (no Godot needed). Run from the LastOneFalls folder:
    python3 tools/static_check.py
Checks: space/mixed indentation in .gd files, res:// paths that do not exist (optional audio/font/thumbnail
paths are only warned about), EN/AR locale key parity, t("key") keys missing from the table, dynamic map keys,
bracket balance. It does NOT replace running the game or tests/*.tscn in Godot 4.3."""
import glob, os, re, sys

OPTIONAL = ("res://assets/audio/", "res://assets/fonts/", "res://assets/maps/map_")
errors, warns = [], []
gd = sorted(glob.glob("scripts/**/*.gd", recursive=True) + glob.glob("tests/*.gd"))

def rd(f):
    return open(f, encoding="utf8").read()

for f in gd:
    s = rd(f)
    for i, l in enumerate(s.split("\n"), 1):
        if l.strip() and not l.strip().startswith("#") and (l.startswith(" ") or re.match(r"^\t* +\t", l)):
            errors.append(f"{f}:{i}: space/mixed indentation")
    t = re.sub(r'"(\\.|[^"\\])*"', '""', s)
    t = re.sub(r"#.*", "", t)
    for a, b in ("()", "[]", "{}"):
        if t.count(a) != t.count(b):
            errors.append(f"{f}: unbalanced {a}{b} ({t.count(a)} vs {t.count(b)})")

for f in gd + glob.glob("scenes/**/*.tscn", recursive=True) + [x for x in ("project.godot", "export_presets.cfg") if os.path.exists(x)]:
    for m in re.finditer(r"res://[\w/\.\-]+", rd(f)):
        p = m.group(0)
        if p.endswith("/") or os.path.exists(p[6:]):
            continue
        (warns if p.startswith(OPTIONAL) else errors).append(f"{f}: missing {p}")

loc = rd("scripts/locale.gd")
cut = loc.index('"ar"')
keys = lambda s: set(re.findall(r'^\t\t"(\w+)":', s, re.M))
en, ar = keys(loc[:cut]), keys(loc[cut:])
for k in sorted(en - ar): errors.append(f"locale: '{k}' missing in AR")
for k in sorted(ar - en): errors.append(f"locale: '{k}' missing in EN")
used = set()
for f in gd:
    used |= set(re.findall(r'\bt\(\s*"(\w+)"', rd(f)))
for k in sorted(used - en): errors.append(f"locale: t(\"{k}\") is not defined")
const = rd("scripts/game_constants.gd")
for k in set(re.findall(r'"(?:key|size_key)":\s*"(\w+)"', const)) | set(re.findall(r'"(map_\w+_desc)"', rd("scripts/map_picker.gd"))):
    if k not in en or k not in ar: errors.append(f"locale: dynamic key '{k}' missing")

for w in warns: print("WARN ", w)
for e in errors: print("ERROR", e)
print(f"{len(errors)} error(s), {len(warns)} warning(s) in {len(gd)} scripts")
sys.exit(1 if errors else 0)
