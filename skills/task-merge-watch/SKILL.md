---
name: task-merge-watch
description: Finish a task after its merge request is sent. Notice the merge with a background watcher, clean up the local branch and worktree, refresh the base branch, and move the task in the tracker. Use when the user asks "did the branch get merged?", "set up a watcher", "tell me when it merges", "clean up after the merge", "update the task status", «проверь, влилась ли ветка», «поставь следилку», «почисти после мержа», «переведи задачу в статус», or after any push that opens a merge request.
---

# After the merge request: verify the merge, clean up, update the task

Work is not finished at the push. It is finished when the merge request is merged, nothing is left
behind locally, and the tracker shows where the task went.

## 1. Is it merged? Use evidence, not one signal

The merge request state on your forge is the authority. Ask it when you can. Git alone can only
collect evidence, and each signal below has failed in practice:

- **`git branch --contains` is not evidence.** A squash merge never puts the branch's commits into
  the base, so a merged branch looks lost. Branches have been deleted as garbage this way.
- **Deleting the branch on origin is not evidence.** Many teams keep branches after merging, and
  others delete them. Wait for deletion and the watcher can stay silent through every merge.
- **A branch missing from origin is a reason to check, not "never pushed".** The merge request ref
  usually survives: `refs/merge-requests/<iid>/head` on GitLab, `refs/pull/<number>/head` on GitHub.

```bash
git fetch origin --prune
git merge-base --is-ancestor origin/<branch> origin/<base> && echo "tip is in base"
```

The tip being in the base is not proof on its own: see "What git cannot tell" below.

For a squash merge, compare commit trees over the files the branch touched, never the working copy:

```bash
# Paths stay NUL-separated and go in as an array.
base=$(git merge-base origin/<base> <branch>)
paths=()
while IFS= read -r -d '' p; do paths+=("$p"); done \
  < <(git diff -z --no-renames --name-only "$base" <branch>)
[ "${#paths[@]}" -gt 0 ] &&
  git --literal-pathspecs diff --quiet --no-renames origin/<base> <branch> -- "${paths[@]}" &&
  echo "contents match"
```

Traps in this recipe:

- **`git apply -R --check` checks the working tree, not the base.** With the branch checked out, the
  reverse of its own patch always applies, so every branch looks merged.
- **A mangled pathspec means an empty diff, and an empty diff means "merged".** Unsplit variables in
  zsh, spaces in filenames and quoted non-ASCII names all produce pathspecs that match nothing.
  `git diff --quiet` then succeeds. Read paths NUL-separated and pass them as an array, with
  `git --literal-pathspecs`.
- **An empty contribution proves nothing.** A branch with no commits of its own, or with commits that
  cancel out, has no diff against the base. Do not read that as "everything is already there".

If a branch is not in the base, also check whether the work was deliberately dropped or replaced
before calling it lost.

## 1a. The watcher: notice merges without checking by hand

`watch-task-branches.sh`, next to this file, passes over all matching local branches and prints one
line per event. Run it in the background, ideally under a tool that wakes the agent on each stdout
line. If that tool has a lifetime limit, restart the watcher when it expires. New branches are picked
up automatically.

```bash
WATCH_REPO=/path/to/repo WATCH_BASE=origin/main \
  bash /path/to/skills/task-merge-watch/watch-task-branches.sh
```

Check a new setup with `WATCH_ONCE=1`: it reports the number of watched branches on stderr, prints
`no-match:` if the pattern finds nothing, and exits non-zero if the fetch failed.

| Variable | Meaning | Default |
|---|---|---|
| `WATCH_REPO` | Repository directory | current directory |
| `WATCH_BASE` | Base ref, must be under `origin/` because only origin is fetched | `origin/HEAD` |
| `WATCH_PATTERN` | Branch filter, a `grep -E` regex, **not a glob** | `^(fix\|feat\|feature\|refactor\|chore)/` |
| `WATCH_INTERVAL` | Seconds between passes | `60` |
| `WATCH_FETCH_TIMEOUT` | Seconds before a hung fetch is killed | `90` |
| `WATCH_ONCE` | One pass, then exit | off |
| `WATCH_STATE` | File of already reported branches, per base | temp file keyed by repository path |

It needs `bash`, `git` 2.39 or newer and `perl` (for the fetch timeout). Branches outside the pattern are
not watched, and `no-match:` only fires when no branch at all matches, so keep the pattern as wide as your
branch names. The base branch is never judged, even if the pattern matches it.

| Event | Meaning |
|---|---|
| `merged:` | Evidence found, named in parentheses: `merge commit`, `same patches`, `file contents match` or `squashed patch` |
| `ambiguous:` | The tip is in the base with no merge commit |
| `gone-unconfirmed:` | The branch left origin and git finds no evidence of a merge. It may have been closed, merged with commits added after the push, or squashed in a way git can't detect. Check the merge request |
| `no-match:` | The pattern finds no local branch other than the base, so nothing is being watched. Printed once per run |
| `fetch-failed:` | Merges are not visible. Printed once per failure streak, at the third failure in a row, and with `WATCH_ONCE` on any failure |
| `fetch-recovered:` | The fetch works again after a reported failure |
| `bad-config:` | The watcher can't run as configured: wrong directory, base not under `origin/` or missing, invalid regex, old git. It exits with code 2 |

Between `fetch-failed:` and `fetch-recovered:`, silence means the watcher cannot see merges, not that
nothing merged.

`merged:` and `ambiguous:` judge what reached origin. If the local branch has commits that are not on
origin, the event says so and `merged:` drops its cleanup cue. Once the branch is gone from origin, the
watcher only has the local tip, so commits added after the push turn the event into `gone-unconfirmed:`,
which counts the commits not reachable from the base.

**An event is a cue to look, not a verdict.** Verify before deleting anything.

### What git cannot tell

These limits need the forge API. All but the last are pinned by tests.

- **Closed without merging, branch kept on origin:** git has no signal, so the watcher stays silent.
- **Squash or rebase merge over an edit within a few lines of the change:** the file contents differ and
  the patch context no longer matches, so the merge is missed, whether or not the files change later. If
  the branch is also deleted on origin, the event is `gone-unconfirmed:`. An edit further away in the same
  file is still found.
- **The same content landed independently:** reported as `merged`, with `same patches` or `file contents
  match`.
- **Pushed without an upstream, then deleted on origin:** looks like a branch that was never pushed.
  Push with `-u`.
- **A fresh branch on a tip that was merged:** a branch with no commits of its own, created at the top of
  another branch that was merged with a merge commit, is reported as `merged`. It is identical to a real
  merge of that tip.
- **Fast-forward merge versus a pushed branch with no own commits:** these are identical in git, so
  both are reported as `ambiguous`. Teams that fast-forward will see this for every merge, and should
  check the merge request or replace the watcher's verdict with an API call.

Tests: `bash tests/run-tests.sh`, run from this skill's folder, builds throwaway repositories and runs the merge, open-branch, failure and limit scenarios. A real fast-forward merge is not among them; the pushed-with-no-commits side of that pair is.

## 2. Clean up

Look first. `--force` and `-D` destroy uncommitted changes and unpushed commits without asking, and
the watcher sees neither working trees nor anything beyond what it reports:

```bash
git -C <tree-holding-the-branch> status --short   # must print nothing
git log origin/<branch>..<branch>                 # must print nothing
```

If either prints anything, stop and tell the user. If `origin/<branch>` is gone, the second command
fails: compare the branch with what the merge request contains before going on.

Only then. If the branch has its own worktree:

```bash
git worktree remove <path> --force && git worktree prune
```

If it is checked out in the main tree instead, switch that tree to another branch first: git refuses to
delete a branch that is checked out. Then:

```bash
git branch -D <branch>
git stash list        # should be empty
```

Update the local base without touching a tree that may hold other work:

```bash
git fetch origin <base>:<base>
```

If `<base>` is checked out in a tree, git refuses that command and `origin/<base>` stays old. Run
`git fetch origin <base>`, then in that tree check `git status --short` and run
`git merge --ff-only origin/<base>`.

Before dropping a stash, compare it to history: `git log origin/<base> --oneline -3 -- <file from the
stash>`. The work has often been redone under another task. If its content exists nowhere else, do
not drop it. Tell the user.

## 3. Update the task

Fill in your tracker's details here:

- **Status after merge:** `<status meaning "on the shared environment, awaiting verification">`.
  Usually not "done": whoever verifies the task closes it.
- **Status name exceptions:** `<projects with a different flow>`.
- **How to write:** follow the `tracker-task` skill if you use it, or your team's own method.

Rules that hold for any tracker:

- **Write to the tracker only when the user asked for it,** and show the exact status change and comment
  text for a yes first. Never verify a fix in production.
- **Re-read the current status first.** It may have changed since you last looked.
- **A 403 on a write may be a missing CSRF token, not missing permissions.** Check before asking for
  more access.
- **In a comment, say** what caused the defect, what changed, where the merge request is, and how to
  verify it on the shared environment.

## 4. Do not close someone else's work

If the task is already with a reviewer, do not move it to "done" for them. If it is already done,
there is nothing to change. Report it to the user rather than finishing from memory.
