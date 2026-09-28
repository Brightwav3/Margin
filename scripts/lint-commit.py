#!/usr/bin/env python3
"""Kontrola Conventional Commits a pravidel repozitáře. Sdílí ji hook commit-msg, scripts/check.sh a CI.

Použití:
  lint-commit.py --message-file F          (soubory ze staged; voláno z commit-msg)
  lint-commit.py --range A..B              (všechny commity v rozsahu; check.sh, CI)
  lint-commit.py --title "feat(ui): ..."   (jen hlavička, např. PR title)
  lint-commit.py --check-branch NAME       (název větve)
"""
import re, sys, os, subprocess, argparse

TYPES = 'feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert'
SCOPES = {'core', 'ui', 'api', 'agent', 'vault', 'editor', 'tasks', 'capture', 'graph', 'plan', 'docs', 'ci', 'deps', 'tooling'}
UI_RE = re.compile(r'^(Sources/MarginUI/|App/Margin/|Tests/MarginUITests/|Tests/Snapshots/)')
CORE_RE = re.compile(r'^(Sources/MarginCore/|App/Platform/|Tests/MarginCoreTests/|Tests/Conformance/|Tests/Fixtures/)')
API_RE = re.compile(r'^Sources/MarginCore/API/')
PROTECTED_RE = re.compile(r'^(\.githooks/|\.claude/settings\.json|scripts/(lib\.sh|claude-guard\.(sh|py)|land\.sh|lint-commit\.py))')
CODE_RE = re.compile(r'^(Sources|App|Tests)/.*\.swift$')
HEADER_RE = re.compile(rf'^(?P<type>{TYPES})(\((?P<scope>[a-z0-9-]+)\))?(?P<bang>!)?: (?P<desc>\S.*)$')
TASK_RE = re.compile(r'(?m)^Tasks?: *(?P<ids>.+)$')
ID_RE = re.compile(r'^(M\d{1,2}[abc]?-\d{2}(\.[BU])?|AG-\d{2})$')
ISSUE_RE = re.compile(r'(?mi)^(closes|fixes|refs|resolves) #\d+')
BRANCH_RE = re.compile(rf'^(wip/)?({TYPES})/[a-z0-9]+(-[a-z0-9]+)*$')
NEEDS_TASK = {'feat', 'fix', 'refactor', 'perf', 'test'}
NO_CODE = {'docs', 'ci', 'chore', 'style'}
HELP = ' (viz docs/git-workflow.md)'


def lint_header(header):
    errs = []
    m = HEADER_RE.match(header)
    if not m:
        errs.append(f'Špatný formát hlavičky: "{header}"\n    Očekáváno: <type>(<scope>): <popis>   např. "feat(ui): add course card banner"\n'
                    f'    types: {TYPES.replace("|", ", ")}\n    scopes: {", ".join(sorted(SCOPES))}')
        return errs, None
    if len(header) > 72: errs.append(f'Hlavička má {len(header)} znaků, maximum je 72.')
    d = m.group('desc')
    if d[0].isupper(): errs.append('Popis začíná malým písmenem a je v rozkazovacím způsobu ("add", ne "Added").')
    if d.endswith('.'): errs.append('Popis nekončí tečkou.')
    if re.fullmatch(r'(wip|tmp|test|asdf|update|changes|stuff|fix)', d.lower()): errs.append('Popis nic neříká.')
    if m.group('scope') and m.group('scope') not in SCOPES:
        errs.append(f'Neznámý scope "{m.group("scope")}". Povolené: {", ".join(sorted(SCOPES))}')
    return errs, m


def lint(message, files, landing=False):
    first = message.strip().split('\n', 1)[0]
    if first.startswith(('Merge ', 'Revert "', 'fixup!', 'squash!')): return []
    errs, m = lint_header(first)
    if not m: return errs
    t, scope, bang = m.group('type'), m.group('scope'), bool(m.group('bang'))
    if landing or not files: return errs      # při landingu se cesty kontrolovaly u jednotlivých commitů
    ui = [f for f in files if UI_RE.match(f)]
    core = [f for f in files if CORE_RE.match(f)]
    api = [f for f in files if API_RE.match(f)]
    prot = [f for f in files if PROTECTED_RE.match(f)]
    code = [f for f in files if CODE_RE.match(f)]
    if ui and core and scope != 'api':
        errs.append('Commit mění backend (core) i UI zároveň. Rozděl ho na dva commity, nebo jde-li o změnu smlouvy, použij scope api.')
    if api:
        if scope != 'api': errs.append('Změna Sources/MarginCore/API vyžaduje scope api (docs/plan/09-contracts.md §1).')
        if not any(f.startswith('Tests/Conformance/') or f == 'docs/plan/09-contracts.md' for f in files):
            errs.append('Změna smlouvy musí ve stejném commitu upravit Tests/Conformance/ nebo docs/plan/09-contracts.md.')
    if scope == 'ui' and core: errs.append('Scope ui, ale commit mění backend soubory.')
    if scope in ('core', 'vault') and ui: errs.append(f'Scope {scope}, ale commit mění UI soubory.')
    if code and t in NO_CODE: errs.append(f'Typ {t} nesmí měnit Swift kód v Sources/, App/, Tests/. Použij feat/fix/refactor/test.')
    if t == 'test' and [f for f in files if f.startswith(('Sources/',)) and CODE_RE.match(f)]:
        errs.append('Typ test smí měnit jen Tests/.')
    if code and t in NEEDS_TASK and not scope: errs.append('Commit s kódem musí mít scope (ui, core, api, agent, vault, editor, tasks, capture, graph).')
    if prot and not (t == 'chore' and scope == 'tooling'):
        errs.append('Commit mění chráněné soubory (.githooks, scripts/lib.sh, guard, land.sh, lint-commit.py, .claude/settings.json). Smí je měnit jen člověk a jen jako chore(tooling).')
    if code and t in NEEDS_TASK:
        ids = []
        tm = TASK_RE.search(message)
        if tm: ids = [x.strip() for x in re.split(r'[,\s]+', tm.group('ids')) if x.strip()]
        bad = [x for x in ids if not ID_RE.match(x)]
        if bad: errs.append(f'Neplatné ID úkolu v patičce Task: {", ".join(bad)} (např. Task: M3-05, M5-03.B, AG-04)')
        if not ids and not ISSUE_RE.search(message):
            errs.append('Commit s kódem musí mít patičku "Task: M3-05" (ID z docs/plan/) nebo "Closes|Fixes|Refs #123".')
    return errs


def git(*a, cwd=None):
    return subprocess.run(['git', *a], capture_output=True, text=True, cwd=cwd).stdout


def report(errs, label=''):
    if not errs: return 0
    sys.stderr.write('\n✗ ' + (label + ': ' if label else '') + 'porušení pravidel commitu\n')
    for e in errs: sys.stderr.write('  - ' + e + '\n')
    sys.stderr.write('  Pravidla: AGENTS.md a docs/git-workflow.md\n\n')
    return 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--message-file'); ap.add_argument('--range'); ap.add_argument('--title'); ap.add_argument('--check-branch')
    a = ap.parse_args()
    landing = os.environ.get('MARGIN_LANDING') == '1'
    if a.check_branch:
        b = a.check_branch
        if b in ('main', 'master'): return 0
        if not BRANCH_RE.match(b):
            return report([f'Název větve "{b}" nesplňuje <type>/<scope>-<slug>, např. feat/ui-course-card, fix/core-frontmatter-crlf, docs/plan-status. (wip/ prefix je volitelný)'], 'větev')
        return 0
    if a.title:
        errs, _ = lint_header(a.title); return report(errs, 'PR title')
    if a.message_file:
        msg = ''.join(l for l in open(a.message_file, encoding='utf-8') if not l.startswith('#'))
        files = [f for f in git('diff', '--cached', '--name-only').split('\n') if f]
        return report(lint(msg, files, landing), 'commit')
    if a.range:
        rc = 0
        for sha in [s for s in git('rev-list', '--reverse', '--no-merges', a.range).split('\n') if s]:
            msg = git('log', '-1', '--format=%B', sha)
            files = [f for f in git('diff-tree', '--no-commit-id', '--name-only', '-r', '--root', sha).split('\n') if f]
            rc |= report(lint(msg, files, False), f'commit {sha[:8]}')
        return rc
    ap.print_help(); return 2


if __name__ == '__main__':
    sys.exit(main())
