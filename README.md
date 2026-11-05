# Agent Workflow Skills

Eleven skills for coding agents, covering a developer's working day: take a batch of tasks, run them in parallel, verify the result, follow each merge request to the end, and report on the work.

They grew out of daily use on real multi-repository projects. Most rules exist because something went wrong without them. This public set is rewritten for publication: project details are removed and the examples are illustrative.

**Authorship:** direction, design decisions, and review: Katherine Mironova. Implementation used Claude Code and OpenAI Codex under her direction.

> **Коротко по-русски.** Набор из одиннадцати скиллов для ИИ-агентов: параллельная работа над задачами, проверка результата, доведение MR до конца и отчёты. Скиллы выросли из ежедневной работы и переписаны для публикации, без данных рабочих проектов. Ниже есть указатель и примеры того, как их сочетать.

## Which skill does what

| Skill | Use it when | What you get |
| --- | --- | --- |
| [`task-dispatch`](skills/task-dispatch/SKILL.md) | Several tasks arrive at once | Each task has its own branch and merge request; suitable ones go to parallel agents |
| [`task-merge-watch`](skills/task-merge-watch/SKILL.md) | A merge request is sent | A background watcher reports likely merges of local task branches; you confirm, clean up and update the tracker |
| [`tracker-task`](skills/tracker-task/SKILL.md) | A task needs a card, or a finished one needs filling in | A card written through your logged-in browser tab; you approve the exact text first |
| [`tracker-visual-evidence`](skills/tracker-visual-evidence/SKILL.md) | **Frontend:** a visual fix needs proof | Honest before/after screenshots with clear markings, attached to the card |
| [`screen-visual-audit`](skills/screen-visual-audit/SKILL.md) | **Frontend:** you need to check how a screen looks | One screen checked across your browser and viewport matrix, with a plain list of what was not checked |
| [`backend-drift`](skills/backend-drift/SKILL.md) | **Frontend:** a field on screen is empty or wrong | The exact break in the data chain, split into "fix on the frontend" and "question for the backend team" |
| [`openapi-contract`](skills/openapi-contract/SKILL.md) | You need to know what an endpoint accepts or returns | An answer from a saved copy of the API spec, optionally confirmed by a live request to a non-production environment |
| [`refactor-code`](skills/refactor-code/SKILL.md) | A file or folder needs a review and cleanup | A full list of findings first, then behavior-preserving fixes |
| [`refactor-parent`](skills/refactor-parent/SKILL.md) | **Frontend:** a shared component has drifted across its users | The parent becomes the single source of truth, and every child is audited against it |
| [`refactor-log`](skills/refactor-log/SKILL.md) | Significant work is finished | A log entry with hashes and numbers taken from git, plus summaries for a period |
| [`work-report`](skills/work-report/SKILL.md) | You need a report for a period | The log reconciled against git, then a technical or business report |

## How to combine them

The prompts below are examples. Agents pick a skill by its description, or you can call it by name.

### A batch of tasks

> "Here are five tasks. Run them in parallel where you can."

1. `task-dispatch` separates independent tasks from the ones that need your decision, and gives each its own branch.
2. `tracker-task` fills in each card with what was done and how to check it.
3. `task-merge-watch` reports likely merges. After a check, it cleans up and moves the task along.
4. `refactor-log` records the finished work.

### A field is empty on screen

> "This column is empty. Is it the frontend or the backend?"

1. `backend-drift` walks the chain from the database to the rendered cell.
2. `openapi-contract` confirms what the endpoint really returns.
3. If the fix is on the frontend, make it and continue with `tracker-task` and `task-merge-watch`. If it isn't, the result is a precise question for the backend team.

### Cleaning up a shared component

> "Our table wrapper has drifted. Clean it up and check everything that uses it."

1. `refactor-parent` lists findings for the parent and each child, then moves shared behavior into the parent.
2. `screen-visual-audit` checks the affected screens.
3. `tracker-visual-evidence` documents any visible fix.
4. `refactor-log` records the result.

For one file rather than a shared component, start with `refactor-code`.

### A layout defect with proof

> "This dialog is cut off on a tablet. Fix it and show before and after."

1. `screen-visual-audit` reproduces the defect and names what could be checked.
2. `tracker-visual-evidence` captures both states and marks the difference.
3. `tracker-task` holds the card that the evidence is attached to.

### A report for your manager

> "Make a report for this quarter, without technical terms."

1. `refactor-log` keeps the entries during the period.
2. `work-report` finds what the log missed, shows you the gaps, and then writes the report.

## Lessons behind the skills

- **Agents working in parallel share more than they appear to.** `git stash` is shared across worktrees, so one agent can pop another's work. `task-dispatch` forbids it.
- **A hook can break code after your check.** An autofix at commit time can change behavior, so the type check runs again after the commit.
- **Silence should not pass for "nothing happened".** The merge watcher reports repeated fetch failures and warns when no branch matches its pattern. Its skill file lists the cases it still can't see.
- **Git cannot always prove a merge.** The watcher treats an event as a reason to look, and `task-merge-watch` lists the cases git alone can't settle.
- **A success response is not proof.** A tracker can answer 200 and ignore a field, so `tracker-task` reads the card back after writing.

## What is tested

The merge watcher has a test suite that builds throwaway git repositories, including its known limits:

```bash
bash skills/task-merge-watch/tests/run-tests.sh
```

Every other skill is written guidance for an agent and has no automated tests. Its results depend on the agent and the project, so review what it produces.

## Installation

Each skill is a folder with a `SKILL.md`. Copy the ones you need into your agent's skills directory:

```bash
# Claude Code, for all projects (or .claude/skills/ in one repository)
mkdir -p ~/.claude/skills && cp -R skills/task-dispatch ~/.claude/skills/

# Codex
mkdir -p ~/.codex/skills && cp -R skills/task-dispatch ~/.codex/skills/
```

Some skills depend on others or on your setup:

- `tracker-visual-evidence` needs `tracker-task`.
- `work-report` reads the log that `refactor-log` keeps.
- `tracker-task` needs a tool that lets the agent use your browser, such as a browser extension for your agent.

Some skills have a section for your own settings, such as the repository map or the browser matrix. Fill those in before first use.

## License

[MIT](LICENSE)
