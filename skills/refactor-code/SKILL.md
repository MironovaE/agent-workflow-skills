---
name: refactor-code
description: Review and clean up a file or folder for correctness, simplicity, readability, speed, decomposition and proper use of the UI library, without changing behavior. Use when the user says "check whether X is correct", "refactor / clean up this file", "is this overengineered", "are there needless fallbacks", "this file is a 1000-line wall", "can this be simpler / faster", "any logic errors", or «глянь, всё ли корректно», «отрефачь», «почисти этот файл», «можно ли упростить». For a shared parent component and its consumers, use refactor-parent instead.
---

# Review and refactor a piece of code

A general pass over a file or folder. If the job is to bring a shared wrapper and all of its
children into shape, use `refactor-parent` instead.

Do not change behavior during a refactor: change structure and quality only. If you find behavior
that should change (a bug, a fallback that alters the result), **say so and ask**. The final word
belongs to the user.

## The bar

Level: **a senior or staff engineer in a codebase that lives for years and is read by dozens of
people.** The bar is about the maturity of the solution, not the volume of code.

**What the bar means (do):**

- Fix the cause, not the symptom. If a change is a patch over a wrong data model or someone else's
  broken contract, say so out loud instead of papering over it.
- Think through edge cases before a user finds them: empty / `null` / network error / race / double
  click / very long text / no permission.
- Name the trade-off. Every non-trivial decision has a price; say it, don't hide it.
- Finish what is in scope. A half-implementation looks like it works, which makes it worse than none.
- Leave code the next person understands without you: full names, straight data flow, comments on
  *why*, not *what*.

**What the bar is NOT (don't):**

- Not volume or layer count. An abstraction with no second consumer is debt, not maturity.
- Not "enterprisey": factories, just-in-case generics and config objects for a single call lower the
  bar.
- Not rewriting working code to your taste.
- Not defensive programming: `?? ''` and `|| []` "just in case" hide a bug instead of catching it.

The formula: **maturity up, amount of code down.** If raising the bar made you add layers, the bar
did not go up.

## 0. Frame it (think before code)

- **Scope.** Fix the list of files and state it. If the work seems to need something outside the
  list, name it and ask before going further.
- **The canon.** Read the repository's instructions (`AGENTS.md` / `CLAUDE.md` / `CONTRIBUTING`). If
  a file is too large to load, pull the relevant sections explicitly (`grep -n '^#'`, then `sed`). At
  minimum: code style, component architecture, refactoring rules, the list of anti-patterns.
- **The reference.** Find the project's best implementation of the same kind and compare structure
  against it. A worked example is more precise than a description.
- Read the target in full. State what it does, its public API and its consumers (`grep` the imports).
  Don't guess: state assumptions and clarify anything ambiguous.
- Pull UI library docs from a current source (the library's MCP server if there is one, otherwise the
  official docs for the installed major), not from memory. Classes, tokens and defaults change between
  versions.

## 1. Inventory (find everything, don't fix yet)

List all findings first, then edit. An agent that searches and fixes at the same time optimizes for
"made an edit", not "found everything", and the middle of the scope gets neglected.

Write down **every** finding with a tag:

- `[fix]`: preserves behavior, doing it now;
- `[ask]`: changes behavior or UX, needs permission;
- `[leave]`: with the reason (legacy, someone else's area, costs more than it gives).

Show the list to the user before editing.

Make two passes and keep them separate, or the first flaw you find will pull you off the route.

### Pass A: correctness (matters most)

- Logic errors, races, wrong hook dependencies, mutations, lost branches, off-by-one errors.
- The edge cases from the bar: empty, `null`, request failure, no permission.
- Fallbacks that mask a bug: `?? ''`, `|| []`, "just in case" defaults the requirements don't ask for.

### Pass B: quality and structure

- **Overengineering:** one-off abstractions, features "for the future", wrappers with no second
  consumer: inline them. Delete config that duplicates library defaults.
- **Walls of code:** split a file that mixes several responsibilities into UI blocks, logic, pure
  transformations and config, each in its place, and keep the orchestrator thin. Length alone is only
  a signal to look: a long file with one responsibility can stay whole.
- **Dead and murky code:** dead code, nested ternaries, duplicates, poor names.
- **UI library:** the right components and props instead of hand-rolled ones; shared defaults in the
  theme, not in each component; colors and typography through tokens, not local values.
- **Readability:** the project's conventions for exports and function declarations; a trivial body
  without needless wrapping.
- **Speed:** unnecessary re-renders and recalculations; memoization only where it pays off, no cargo
  cult.

### What does NOT count as refactoring (it only adds noise to the diff)

- Renaming for the sake of renaming.
- Docstrings on everything. They belong on the public API, not on every local function.
- Splitting a small file "for symmetry". Split by responsibility, not by length.
- Memoizing something that isn't recalculated anyway.
- Swapping a working construct for a fashionable one with the same result.

## 2. Apply

- Behavior-preserving changes: do them now, and don't economize on diff size.
- Behavior changes: ask.
- Look for something existing before writing anything new. A new shared abstraction needs a real
  second consumer. Splitting one file into local parts by responsibility does not.

## 3. Verify (don't skip)

- Types, lint and format through the project's real commands (read `package.json` and configs, don't
  guess), on the changed files, at the same strictness as CI.
- **Fresh eyes.** The author of a change is a poor judge of it: the context is polluted by
  justifications they invented along the way. Give a subagent with a clean history the whole change and
  the task "find where this got worse: broken behavior, a lost branch, an unnecessary abstraction, a
  violation of the repository's conventions". The whole change means the diff against the merge base
  plus the new files, as in the scan below: a bare `git diff` misses committed, staged and untracked
  work, and refactoring moves code into new files. Work through its findings; don't take them on faith.
- If UI changed, run a real scenario (smoke or e2e). Types alone are not enough.

## 4. Loose ends and definition of done

- **Scan for loose ends** before saying "done" or proposing anything new. Cover committed, staged,
  unstaged and new files:

  ```bash
  BASE=$(git merge-base origin/<default-branch> HEAD) && {
    PATTERN='TODO|FIXME|XXX|HACK|eslint-disable|@ts-ignore|@ts-expect-error|noqa'
    git --no-pager diff "$BASE" | grep -E '^\+' | grep -E "$PATTERN"
    git ls-files --others --exclude-standard -z | xargs -0 grep -nHE "$PATTERN" /dev/null
  }
  ```

  Either finish each one in this session or write it down as an explicit item right away.
- **Done means the machine agrees.** If the project has a machine criterion for "this area is in order"
  (a strict lint preset, a type check, a coverage gate), done means it passes, not that things
  subjectively improved.
- Check the "before you say done" checklist in the repository's instructions, if there is one.
