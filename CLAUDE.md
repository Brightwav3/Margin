@AGENTS.md

## Specifika pro Claude Code
- Při startu session dostaneš přehled stavu (`scripts/agent-brief.sh`). Bez přečtení `docs/plan/STATUS.md` nezačínej.
- Hooky v `.claude/settings.json` (`scripts/claude-guard.sh`) blokují obcházení pravidel (`--no-verify`, holý force push, force do `main`, úpravy hooků, zápis schválení). Blokace není chyba, ale pravidlo: oprav příčinu nebo řekni uživateli, proč to nejde.
- Guard čte větev před spuštěním příkazu: `git switch -c …` a `git commit …` musí být **dvě samostatná volání**, ne jeden příkaz.
- Souběžná práce více agentů: každý ve vlastním git worktree (`git worktree add ../Margin-<slug> -b <type>/<scope>-<slug>`), jedna větev na PR.
- Tvoje větev práce je určena úkolem: **backend** (`docs/plan/backend/`) nebo **UI** (`docs/plan/ui/`). Nemíchej je v jednom commitu (kromě scope `api`).
- Commit zprávu s patičkou piš takto (dva `-m`, druhý = patička): `git commit -m "feat(ui): add course card banner" -m "Task: M3-01"`.
