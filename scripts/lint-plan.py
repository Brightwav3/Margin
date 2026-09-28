#!/usr/bin/env python3
"""Kontrola konzistence plánu: unikátní ID úkolů, součty vah v sekcích, souhrnech, docs/plan/11 a STATUS.md."""
import re, sys, os
ROOT = os.popen('git rev-parse --show-toplevel').read().strip() or '.'
P = os.path.join(ROOT, 'docs/plan/')
errs = []

def rd(p):
    try: return open(P + p, encoding='utf-8').read()
    except FileNotFoundError:
        errs.append(f'chybí soubor docs/plan/{p}'); return ''

def parse(readme):
    s = rd(readme); ids = {}; sec_sum = {}; sec_head = {}; summary = {}; sigma = None
    parts = re.split(r'(?m)^## (?=M)', s)[1:]
    for part in parts:
        head = part.split('\n', 1)[0]
        name = head.split(' — ')[0].strip()
        m = re.search(r'\(váha (\d+)\)\s*$', head)
        sec_head[name] = int(m.group(1)) if m else None
        tot = 0
        for l in part.split('\n'):
            r = re.match(r'^\| ([A-Z]+\d*-\d+(?:\.[BU])?) \|.*\| (\d+) \|[^|]*\|\s*$', l)
            if r:
                if r.group(1) in ids: errs.append(f'{readme}: duplicitní ID {r.group(1)}')
                ids[r.group(1)] = 1; tot += int(r.group(2))
        sec_sum[name] = tot
    for l in s.split('\n'):
        r = re.match(r'^\| (M\w+) \| [^|]* \| (\d+) \|\s*$', l)
        if r: summary[r.group(1)] = int(r.group(2))
        r = re.match(r'^\| \*\*Σ\*\* \| \| \*\*(\d+)\*\* \|', l)
        if r: sigma = int(r.group(1))
    for k, v in sec_sum.items():
        if sec_head.get(k) is not None and sec_head[k] != v: errs.append(f'{readme}: sekce {k} má v nadpisu váhu {sec_head[k]}, součet úkolů je {v}')
        if k in summary and summary[k] != v: errs.append(f'{readme}: souhrn {k}={summary[k]}, součet úkolů je {v}')
    if sigma is not None and sigma != sum(sec_sum.values()): errs.append(f'{readme}: Σ={sigma}, součet je {sum(sec_sum.values())}')
    return ids, sec_sum

ib, sb = parse('backend/README.md'); iu, su = parse('ui/README.md')
allids = set(ib) & set(iu)
if allids: errs.append(f'ID v obou větvích současně: {sorted(allids)}')
tb, tu = sum(sb.values()), sum(su.values())

s11 = rd('11-schedule-and-gates.md')
for l in s11.split('\n'):
    r = re.match(r'^\| \d+ \| (M\w+) \| .*? \| (\d+) \| (\d+) \| (\d+) \|', l)
    if r:
        m, b, u, t = r.group(1), int(r.group(2)), int(r.group(3)), int(r.group(4))
        if sb.get(m, 0) != b or su.get(m, 0) != u or b + u != t: errs.append(f'11-schedule: {m} má {b}/{u}/{t}, README má {sb.get(m,0)}/{su.get(m,0)}')
    r = re.match(r'^\| \| \*\*Σ\*\* \| \| \*\*(\d+)\*\* \| \*\*(\d+)\*\* \| \*\*(\d+)\*\*', l)
    if r and (int(r.group(1)), int(r.group(2)), int(r.group(3))) != (tb, tu, tb + tu): errs.append(f'11-schedule: Σ {r.groups()} ≠ ({tb},{tu},{tb+tu})')

st = rd('STATUS.md')
for l in st.split('\n'):
    r = re.match(r'^\| (M\w+) \| .*? \| (\d+) \| (\d+) \| (\d+) \|', l)
    if r:
        m, b, u, t = r.group(1), int(r.group(2)), int(r.group(3)), int(r.group(4))
        if sb.get(m, 0) != b or su.get(m, 0) != u or b + u != t: errs.append(f'STATUS: {m} má {b}/{u}/{t}, README má {sb.get(m,0)}/{su.get(m,0)}')
    r = re.match(r'^\| \| \*\*Σ\*\* \| \*\*(\d+)\*\* \| \*\*(\d+)\*\* \| \*\*(\d+)\*\*', l)
    if r and (int(r.group(1)), int(r.group(2)), int(r.group(3))) != (tb, tu, tb + tu): errs.append(f'STATUS: Σ {r.groups()} ≠ ({tb},{tu},{tb+tu})')
# Každé Q v STATUS je unikátní
qs = re.findall(r'(?m)^\| (Q\d+) \|', st)
if len(qs) != len(set(qs)): errs.append('STATUS: duplicitní Q')
# ADR ID unikátní
ds = re.findall(r'(?m)^### (D-\d+) ', rd('DECISIONS.md'))
if len(ds) != len(set(ds)): errs.append('DECISIONS: duplicitní D-ID')

if errs:
    print('lint-plan: NALEZENY PROBLÉMY', file=sys.stderr)
    for e in errs: print('  - ' + e, file=sys.stderr)
    sys.exit(1)
print(f'lint-plan: OK (backend {tb}, UI {tu}, Σ {tb+tu})')
