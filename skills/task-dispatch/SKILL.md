---
name: task-dispatch
description: Split a batch of tasks across repositories and delegate the suitable ones to parallel subagents, each task with its own branch, commit and merge request. Use when the user drops several tasks at once, keeps adding "parallel task if possible", says "split these up", "one agent per task", "let's do these in parallel", «раскидай задачи», «по агенту на задачу», «давай в параллель», or wants to work through a task backlog fast.
---

# Task dispatch: work through a batch of tasks in parallel

The user sends many tasks in a row, some touching frontend and backend, some only one side. The goal
is to close them fast without losing control or quality.

## 0. Pull the backlog from the tracker

Instead of having tasks listed by hand, read them from the tracker when you can.

- **Read before you assume access.** Internal trackers often need a VPN or a logged-in browser
  session. If the request times out, ask about the network first.
- **Order the work:** tasks returned from review first, then new ones. Skip tasks waiting on someone
  else or on hold. Within a group, go by priority.
- **For a returned task, read the latest comment.** It usually is the brief for the fix.
- **Read attachments, not only the text.** A reviewer's screenshot often carries the actual point.
- **Do not trust "frontend" or "backend" labels** unless you have checked them against real tasks.
  Decide the side from what the task actually requires.
- **Read only by default.** Write to the tracker only when the user explicitly asks.

## 1. Repository map

Fill this in for your project:

| Repository | Path | Role | Base branch | Notes |
|---|---|---|---|---|
| `<frontend>` | `<path>` | `<stack>` | `<base>` | |
| `<backend>` | `<path>` | `<stack>` | `<base>` | `<is the working tree often busy? use a worktree>` |

A repository's own instructions (`AGENTS.md`, `CONTRIBUTING`) outrank habits from the others. Base
branches can differ between repositories, so do not assume one.

If a working tree may hold someone's paused work, do not `checkout` or `pull` in it. Read contracts
with `git show origin/<base>:<path>` and work in a separate worktree.

## 2. The rule: one task = one branch + commit + merge request

- Branch from a **fresh** base: `git fetch origin <base>`, then
  `git worktree add -b <type>/<number>-<slug> <path> origin/<base>`. In a tree you know is free,
  `git checkout -b <type>/<number>-<slug> origin/<base>` does the same job.
- Put the task number in the branch name and the commit message. Ask for it if you were not given one.
- **A task spanning frontend and backend gets one branch per repository**, so two merge requests.
- **Related tasks** may share a branch if the user confirms.
- **Two "separate" tasks touching the same code** will conflict as separate branches. Use one branch
  with two commits, or stack the second after the first merges. Show the user the choice.
- **A push is outward-facing: confirm with the user first**, do not push by default.
- **Multi-line text in push options:** on GitLab, `-o merge_request.create` can open the merge request,
  but push options reject newlines (`fatal: push options must not have new line characters`, and
  nothing is pushed). Keep the description in a file and join its lines with `<br>`.
- **After a merge, prune:** `git fetch origin --prune`, then remove what you confirmed is merged and
  `git worktree prune`. See `task-merge-watch`. Do not delete the current branch or anything with an
  open merge request.

## 3. Do it yourself or delegate

**Do it yourself:** tasks with forks, diagnostics or judgement calls; UI bugs that need reproducing in
a browser; changes to shared code; cross-service changes; anything that needs a product or
architecture answer.

**Delegate:** self-contained, well-specified changes, such as adding a field or fixing a sort. Start
agents in isolated worktrees, several in one message so they run in parallel.

Give each agent:

- exact context and pointers to the relevant files;
- every operating rule from this skill, because it will not see them otherwise;
- the instruction not to guess ambiguities silently, and to list them in its final report;
- the ban on `git stash` (below).

Take from its report: changed files, typecheck, lint and test results, merge request links, open
questions. Check the claims your decision depends on yourself.

## 4. Verify

- **Use the project's real commands**, read from `package.json` and its configs. A root TypeScript
  config with only references can make a bare `tsc --noEmit` pass without checking anything.
- **Before pushing:** typecheck, lint and relevant tests are green.
- **UI bugs:** reproduce them in a browser, on a test environment or locally, never in production.
- **Credentials:** the user logs in. Never type passwords into a form.

## 5. Forks and blockers: do not guess

- **Product and architecture forks go to the user** and stay open until answered. Picking silently
  takes the decision away from them.
- **Show blockers as soon as you find them.** Do not quietly work around "the backend does not support
  this filter".
- **Fix missing data properly,** with a migration or seed rather than by hand, and record it.

## 6. Wrap up the batch

- A **merge request register:** per task, the side, the merge request and its status.
- **Open questions** from agents and from you, as explicit items.
- **Handoffs** to another team and **declined** tasks.
- A log entry, if the project keeps one. See `refactor-log`.

## `git stash` is shared across worktrees: ban it for agents

`refs/stash` lives in the shared `.git`, not in the worktree, so all parallel agents share one stack.

- `git stash pop` in one worktree can take **another agent's** entry and pull its work into the wrong
  branch.
- `lint-staged` makes its own automatic stash at commit time. If another agent stashes at that moment,
  the indexes shift and the hook fails with `lint-staged automatic backup is missing!`, leaving no
  commit.

So:

- **Forbid `git stash` in the agent prompt.** For a clean baseline use `git diff` or
  `git show <ref>:<path>`.
- **Warn about `lint-staged automatic backup is missing`.** It is not the agent's fault. Check
  `git diff --cached --stat` and commit again. Do not use `--no-verify`.
- **Look at `git stash list` at the end of the batch.** Orphaned entries mean a race happened. Compare
  their content with the branches before dropping anything.

## A hook can break the code after your check

`lint-staged` runs `eslint --fix` on staged files **at commit time**, after you ran the typecheck.
Autofixes can change meaning: a rule that removes a "useless" `undefined` argument breaks a call to a
function that requires one, and the broken build goes into the commit.

**Run the typecheck again after committing**, and require the same from agents in their reports.

## Integration build before pushing

Parallel branches do not see each other. Before pushing, merge them into a throwaway branch in its own
worktree and check:

```bash
if git worktree add -b integration/check <path> <branch-with-shared-code>; then
  (
    cd <path> || exit 1
    for b in <branches>; do
      git merge --no-edit -q "$b" || { echo "CONFLICT $b"; git merge --abort; }
    done
    <typecheck command>
    git diff --name-only --diff-filter=d origin/<base>...HEAD | grep -E '\.tsx?$' | xargs <lint command>
  )
  git worktree remove --force <path>
  git branch -D integration/check
else
  echo "worktree add failed: nothing was merged. Look for a leftover integration/check."
fi
```

The `if` matters: if `worktree add` fails and the steps run anyway, `cd` fails too and the merges land in
the tree you started from, on your own branch. Cleanup also stays inside the `if`, so a failed add can't
remove a worktree that was already at that path.

Without `git merge --abort`, the first conflict leaves the tree unmerged and every later merge fails too.
A branch reported as `CONFLICT` is not in the build, so a green result says nothing about it: settle the
conflict and run the check again.

Pass files to the linter through `xargs`. A list substituted as `$files` can arrive as one argument and
fail with "No files matching the pattern".

## When pipelines go red in a batch

Several merge requests arriving together can make jobs collide in a shared runner directory:
`failed to remove … Directory not empty`, `tsc: not found`, `index.lock`, a broken artifact. **A red
pipeline here does not mean broken code.** First check whether the job reached the tests and what they
reported, then retry jobs **one at a time**, not whole pipelines. Fixing the runner is usually someone
else's job.
