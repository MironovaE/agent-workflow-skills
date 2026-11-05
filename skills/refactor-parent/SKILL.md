---
name: refactor-parent
description: Refactor a shared "parent" component (a wrapper others build on, such as a grid or table wrapper, a shared form, a layout, a design-system primitive) into the single source of truth. Extract styling and behavior into the parent, its utils and small sub-components, then audit every child so each is assembled from the parent with minimal, justified customization. Use when asked to "refactor / clean up the parent", unify a wrapper, make a shared component reusable, cut per-child boilerplate, or «вылизать родителя», «унифицировать обёртку».
---

# Refactor a parent (shared component) to a single source of truth

Goal: someone takes the parent, assembles a child, and customizes minimally, only when a child
genuinely needs it. Everything reusable (styles, behavior, sensible defaults) lives in the parent, its
utils or small sub-components.

Work in phases. Don't skip verification.

## The bar

Level: **a senior or staff engineer in a codebase that lives for years and is read by dozens of
people.** The bar is about the maturity of the solution, not the volume of code.

**What the bar means (do):**

- Fix the cause, not the symptom. If the change is a patch over a wrong data model or a broken
  contract, say so out loud instead of papering over it.
- Think through edge cases before a user finds them: empty / `null` / request failure / race / double
  click / very long text / no permission.
- Name the trade-off. Every non-trivial decision has a price; say it, don't hide it.
- Finish. A half-implementation is worse than none, because it looks like it works.
- Leave code the next person understands without you: full names, straight data flow, comments on
  *why*, not *what*.

**What the bar is NOT (don't):**

- Not volume or layer count. An abstraction with no second consumer is debt, not maturity.
- Not "enterprisey": factories, just-in-case generics and config objects for a single call site lower
  the bar.
- Not rewriting working code to taste.
- Not defensive programming: `?? ''` and `|| []` "just in case" hide a bug instead of catching it.

The formula: **maturity up, amount of code down.** If raising the bar made you add layers, the bar did
not go up.

## 0. Frame it first (think before code)

- **Scope.** Fix the list of files up front and state it. The parent plus its children is already a
  wide diff; don't let it spread further without asking.
- **The canon.** Read the repository's own instructions (`AGENTS.md` / `CLAUDE.md` / `CONTRIBUTING`).
  If a file is too large to load, pull the relevant sections explicitly (`grep -n '^#'`, then `sed`):
  style, component architecture, refactoring rules, the project's anti-patterns, and the section
  covering this kind of parent.
- **The reference.** Open the project's reference implementation of the same kind and check structure
  against it. A worked example beats a prose description.
- Read the parent **in full**. State what it does, its public API and who its children are (`grep` the
  imports).
- Pull the **UI library docs** for anything you touch (an MCP docs server if the project has one,
  otherwise the official docs for the installed major). Never rely on memory, and check the installed
  package when the docs are ambiguous: classes, tokens, defaults and merge semantics change between
  majors.
- Keep behavior identical unless a change is a correctness fix. **Ask before changing behavior.**

## 1. Inventory before you edit (find everything, don't fix yet)

List the findings for the parent **and** for every child first, then start editing. An agent that
searches and fixes at the same time optimizes for "made an edit", not "found everything", and the
middle of the child list is where it stops looking.

Tag every finding:

- `[fix]`: preserves behavior, doing it now;
- `[ask]`: changes behavior or UX, needs permission;
- `[leave]`: with the reason (legacy the project has fenced off, someone else's area, cost beats value).

Show the list before editing. For a parent with many children, this list *is* the plan.

## 2. Reengineer the parent

- **Single source of truth:** move every reusable style and behavior into the parent, or into
  co-located utils or a small sub-component next to it. A child should not re-implement what the parent
  can own.
- **Names:** full, descriptive identifiers, no cryptic abbreviations.
- **Remove cruft:** dead styles, unused props and branches, unnecessary fallbacks and defensive
  `?? ''` / `|| {}` guards, one-off abstractions, features "for the future". Delete, don't comment out.
- **Correctness per the library:** fix patterns that don't match the library's intended API (for
  example wrong class names for the version, or a style merge that clobbers keys), and prefer the
  library's native mechanism over a hand-rolled one when it actually fits.
- **Decompose if bloated:** long file or mixed concerns → extract. Styles → a styles module or const,
  pure logic → utils, sub-UI → sub-components, stateful reuse → a hook. Cohesive units, not artificial
  splitting.
- **No over-engineering:** don't add abstraction for one caller; extract when a second real consumer
  exists.

## 3. Audit the children

- `grep` every consumer of the parent. For each: does it use the parent correctly? Does it re-implement
  something the parent now provides (styles, handlers, defaults)? Is its customization minimal and
  justified?
- Remove per-child duplication that the parent now owns (repeated style selectors, hand-rolled handlers,
  copy-pasted constants).
- Where a child legitimately diverges, keep the override **small and local**. If the same divergence
  appears in **two or more children**, promote it to the parent (a prop or variant) instead of copying
  it. That number is the rule, not a feeling.
- Anything that can't be reduced to the common shape without changing behavior: tag it `[ask]` and show
  it to the user, with what the change would cost. Don't change it on your own, and don't silently work
  around it.

## 4. Verify (do not skip)

- Use the project's package manager and its real typecheck, lint and format commands (read
  `package.json` scripts and configs; don't guess). Lint changed files at the same strictness CI uses,
  and check whether the formatter is already wired in as a lint rule before running it twice.
- **Drive the real UI**, don't just typecheck. If the project has a browser driver (Playwright or
  Cypress) with a login helper and test credentials, write a throwaway spec: reuse the login helper,
  navigate to the affected screen, exercise the flow, assert (computed styles or class presence) **and
  screenshot**. Read the screenshot, iterate on the fix, then delete the temporary spec and its
  artifacts. This catches pixel and behavior regressions you can't see otherwise. If no driver exists,
  at minimum describe the manual check and ask the user to confirm.
- **Contract tests.** If the project keeps harness tests for shared components, run the ones covering
  this parent. If there are none, that absence is itself a finding: say so. Pinned behavior is what lets
  the next refactor be bold instead of careful.
- **Fresh eyes.** The author of a change is a poor judge of it: the context is polluted by the
  justifications they invented along the way. Hand the whole change to a subagent with a clean history:
  "find where this got worse: broken behavior, a lost branch, an abstraction with one consumer, a
  violation of the repository's conventions". The whole change means the diff against the merge base plus
  the new files, as in the scan below: a bare `git diff` misses committed, staged and untracked work, and
  extracted sub-components are new files. Work through its findings; don't take them on faith.

## 5. Wrap up

- **Scan for loose ends** before saying done. Cover committed, staged, unstaged and new files:

  ```bash
  BASE=$(git merge-base origin/<default-branch> HEAD) && {
    PATTERN='TODO|FIXME|XXX|HACK|eslint-disable|@ts-ignore|@ts-expect-error|noqa'
    git --no-pager diff "$BASE" | grep -E '^\+' | grep -E "$PATTERN"
    git ls-files --others --exclude-standard -z | xargs -0 grep -nHE "$PATTERN" /dev/null
  }
  ```

  Either finish each one this session or write it down as an explicit item now.
- **Done means the machine agrees.** If the project has a machine criterion for "this area is in order"
  (a strict lint preset, a type check, a coverage gate), done means it passes, not that things feel
  better.
- Keep the diff coherent; commit on a branch off a fresh default branch. Never stage local-only files
  (for example a gitignored notes or instructions file).
- Suggest a code review before the commit, and remind about any changelog or work-log entry the project
  keeps.
- Record any non-obvious library gotcha you discovered in the project's notes, so the next parent
  refactor is faster.
