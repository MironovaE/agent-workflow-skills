---
name: refactor-log
description: 'Keep a factual log of refactors and achievements for work reports and periodic reviews. Two modes: (1) append an entry after a significant refactor or feature, (2) build a summary for a period, by default a quarter. Use when the user says "log this refactor", "add an entry about what was done", "write this to the log", "make a quarterly summary", "how much did I do this quarter", finishes significant work and wants it recorded, or «запиши в журнал», «залогируй рефакторинг», «составь квартальную сводку».'
---

# Work log: entries and periodic summaries

Why: this log is the record of the work done. The author builds periodic reviews from it, and you build
summaries from it on request. So entries must be **factually exact** (real hashes, real numbers from
git, the real date), never from memory or by eye.

## Configuration

- **Log directory:** `LOG_DIR`, by default `work-log/` at the repository root. Keep it out of
  commits: add it to `.gitignore` or `.git/info/exclude`.
- **Period:** a calendar quarter by default. If the team reviews by month or half-year, change the
  period and the archive naming; the rest of this skill stays the same.

## Files

- `$LOG_DIR/LOG.md`: the **active period**. Newest entries first. No title or summary: the file
  starts directly with `## <date>`.
- `$LOG_DIR/LOG-<period>.md`: the archive of a closed period: `# Work log ...` and
  `## Summary` at the top, then `---` and the entries.
- Quarter by month: Q1 (Jan–Mar), Q2 (Apr–Jun), Q3 (Jul–Sep), Q4 (Oct–Dec).

If more than one agent keeps this log, they must all use the same active file name, or entries will
scatter across two files. Change the scheme in every agent's instructions at once.

---

## Mode 1: append an entry

### Gather the facts from git (don't invent them)

```bash
date +%F                                   # the real entry date (YYYY-MM-DD)
git rev-parse --abbrev-ref HEAD            # current branch
git log -1 --format='%h %s'                # latest commit (or merge commit)
git log --oneline -8                       # to find the branch range or merge hash
git diff --shortstat <base>..<head>        # +N / -N lines and file count for the range
git show --stat <merge-hash>               # if the work landed as a merge commit
```

- **Hashes, file counts and +/- lines come only from git.** A branch range is
  `<branch point>..<last commit>` (or show the merge hash). Test counts come from the test runner's output.
- **The date comes only from `date +%F`.** Convert relative dates ("today") to absolute ones.
- Take the task number from the branch name or commit message. If it isn't there, ask in one word.

### Entry format

```
## YYYY-MM-DD: <short title>

- Commit: `<hash>` (branch `<branch>`, merge `<hash>`, task #NNNN, whichever apply)
- What was done: <description; nested bullets for large work; may split into (frontend) / (backend)>
- Stats: N files, +N / -N lines; tests N → N, if the count changed
- Decisions and why: <key architectural decisions and the motivation>
```

- Large work across a commit range → `Commits: \`A..B\`` instead of one hash. For cross-repository work,
  use separate lines for each repository's commits and what was done there.
- **Achievement vs refactor.** A new feature delivered end to end, or a notable improvement, is an
  achievement: mark the title with `🏆` and say explicitly that it isn't a pure refactor. Ordinary
  structural cleanup has no mark.
- **Flag behavior changes honestly** in a separate entry. If the project changes behavior only with
  permission, the log should show it.

### Where it goes

Put the new entry **at the very top** of `$LOG_DIR/LOG.md`, above the current top entry, with a
blank line between entries. Don't touch anything below it.

---

## Mode 2: period summary

For requests like "make a summary for the quarter" or "how much was done".

1. Read the active `LOG.md` in full.
2. Compute the totals from the entries: number of entries, achievements (🏆) vs refactors, total files
   and +/- lines, recurring themes (screens, tables, forms, API layer, dead code removal and so on).
3. Write a `## Summary` **in the first person, past tense** ("I brought...", "I created..."), by theme
   and effect (less duplication, easier maintenance, quality through types, schemas and pre-commit
   checks). Match the tone of earlier summaries in the archives, if any.
4. Give the summary in chat. Write it to a file only when closing a period (below) or on explicit
   request.

### Closing a period (on request)

- Work out the period being closed from the entry dates.
- At the start of `LOG.md`, add `# Work log`, an intro line, `## Summary` (from mode 2) and
  `---`.
- Rename the file to `$LOG_DIR/LOG-<period>.md`.
- Create an empty `$LOG_DIR/LOG.md` for the new period.

---

## Rules

- Don't invent numbers or hashes: everything comes from git, and the date from `date +%F`.
- Don't commit the contents of the log directory.
- One entry = one significant piece of work (a commit, branch or feature). Don't log every small commit.
- Keep entries terse and to the point. "Decisions and why" is mandatory.
