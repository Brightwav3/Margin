#!/usr/bin/env python3
"""PreToolUse guard pro Claude Code. Čte JSON ze stdin; exit 2 = zablokovat a vrátit agentovi důvod.
Cíl: agent nesmí obejít pravidla (hooky, force push do main, schvalování). Člověk je může měnit sám mimo agenta."""
import json, re, subprocess, sys
try: d = json.load(sys.stdin)
except Exception: sys.exit(0)
tool = d.get('tool_name', ''); ti = d.get('tool_input', {}) or {}


def block(msg):
    sys.stderr.write("✗ GUARD: " + msg + "\n  Pravidla: AGENTS.md, docs/git-workflow.md. Nejde-li to legitimně jinak, řekni to uživateli.\n")
    sys.exit(2)


def current_branch():
    try:
        return subprocess.run(['git', 'symbolic-ref', '--quiet', '--short', 'HEAD'], capture_output=True, text=True, cwd=d.get('cwd') or None).stdout.strip()
    except Exception:
        return ''


PROTECTED = re.compile(r'(^|/)(\.githooks/|\.claude/settings(\.local)?\.json|scripts/(lib\.sh|claude-guard\.(sh|py)|land\.sh|lint-commit\.py|install-hooks\.sh))')
if tool in ('Write', 'Edit', 'NotebookEdit'):
    path = ti.get('file_path', '') or ti.get('notebook_path', '')
    if PROTECTED.search(path):
        block(f"{path} je chráněný soubor (hooky, guard, nastavení, pravidla commitů). Změnu musí udělat člověk.")
    if re.search(r'(^|/)docs/checks/[^/]+\.md$', path):
        text = (ti.get('content') or '') + '\n' + (ti.get('new_string') or '')
        if re.search(r'(?m)^(Stav: Schváleno|Schválil:)', text):
            block("Schválení milestonu (\"Stav: Schváleno\", \"Schválil:\") zapisuje výhradně člověk po vizuální kontrole.")
    sys.exit(0)

if tool == 'Bash':
    c = ti.get('command', '')
    # Odstraníme obsah uvozovek u -m zpráv a heredoc těla, ať se nechytáme na textu commit zprávy
    stripped = re.sub(r'(-m|--message)\s+("([^"\\]|\\.)*"|\'[^\']*\'|\$\'[^\']*\')', r'\1 MSG', c)
    stripped = re.sub(r'<<-?\s*[\'"]?(\w+)[\'"]?.*?\n\1\b', 'HEREDOC', stripped, flags=re.S)
    br = current_branch()

    if re.search(r'git\s+(-\S+\s+)*(commit|push|merge|rebase|am|cherry-pick)\b[^\n;|&]*(\s--no-verify\b|\s-n\b)', stripped) or \
       re.search(r'git\s+(-\S+\s+)*commit\b[^\n;|&]*\s-[a-zA-Z]*n[a-zA-Z]*(\s|$)', stripped):
        block("--no-verify / -n obchází hooky. Oprav příčinu, kterou hook hlásí.")

    push = re.search(r'git\s+(-\S+\s+)*push\b[^\n;|&]*', stripped)
    if push:
        p = push.group(0)
        if re.search(r'--force(?!-with-lease)\b', p) or re.search(r'\s-f\b', p) or re.search(r'\s\+\S', p):
            block("Holý force push (--force, -f, +refspec) je zakázán. Po rebase vlastní větve použij --force-with-lease.")
        if '--force-with-lease' in p:
            if re.search(r'\b(main|master)\b', p) or br in ('main', 'master'):
                block("Force push do main/master je zakázán, ani s --force-with-lease.")

    if re.search(r'git\s+(-\S+\s+)*reset\s+[^\n;|&]*--hard', stripped):
        block("git reset --hard maže práci. Zeptej se člověka.")
    if re.search(r'git\s+(-\S+\s+)*(checkout|restore)\s+(--\s+)?\.(\s|$)', stripped) or re.search(r'git\s+(-\S+\s+)*clean\s+-[a-zA-Z]*f', stripped):
        block("Hromadné zahazování změn (checkout . / restore . / clean -f) je zakázáno bez člověka.")
    if re.search(r'git\s+(-\S+\s+)*config\b[^\n;|&]*(core\.hooksPath|core\.hookspath)', stripped) and 'hooksPath' in stripped and '.githooks' not in stripped:
        block("Měnit core.hooksPath je zakázáno (hooky musí zůstat zapnuté).")
    if re.search(r'git\s+(-\S+\s+)*config\b[^\n;|&]*--unset[^\n;|&]*hooks', stripped, re.I):
        block("Vypínat hooky je zakázáno.")
    if re.search(r'MARGIN_LANDING|MARGIN_HUMAN|MARGIN_ALLOW', stripped):
        block("Proměnné MARGIN_LANDING/MARGIN_HUMAN jsou určeny člověku (a skriptu land.sh). Agent je nenastavuje.")
    if re.search(r'(^|[\s;&|])(rm|mv|cp|sed|perl|chmod|tee|truncate|ln)\b[^\n;|&]*(\.githooks|claude-guard|scripts/lib\.sh|scripts/land\.sh|lint-commit|\.claude/settings)', stripped) or \
       re.search(r'>>?\s*\S*(\.githooks/|claude-guard|scripts/lib\.sh|scripts/land\.sh|lint-commit|\.claude/settings)', stripped):
        block("Hooky, guard, land.sh, lint-commit.py a nastavení Claude Code smí měnit jen člověk.")
    if re.search(r'git\s+(-\S+\s+)*tag\b[^\n;|&]*-accepted', stripped) or re.search(r'git\s+(-\S+\s+)*tag\s+-d\b', stripped):
        block("Tagy *-accepted vytváří jen land.sh po schválení člověkem; tagy se nemažou.")
    if re.search(r'git\s+(-\S+\s+)*branch\s+-[dD]\s+\S*(main|master)\b', stripped):
        block("Větev main se nemaže.")
    if re.search(r'git\s+(-\S+\s+)*commit\b', stripped) and br in ('main', 'master'):
        block(f"Jsi na větvi {br}: commit je zakázán. Vytvoř větev: git switch -c feat/ui-course-card (<type>/<scope>-<slug>).")
sys.exit(0)
