#!/usr/bin/env bash
# Watches local task branches and prints one line per branch that needs attention.
# One stdout line = one event for the agent, including anything that stops it from running.
#
# Settings (environment variables):
#   WATCH_REPO           repository directory (default: current directory)
#   WATCH_BASE           base ref under origin/, e.g. origin/main (default: origin/HEAD).
#                        Only origin is fetched, so any other ref would never move.
#   WATCH_PATTERN        grep -E regex for branch names, NOT a glob
#                        (default: ^(fix|feat|feature|refactor|chore)/)
#   WATCH_INTERVAL       seconds between passes (default: 60)
#   WATCH_FETCH_TIMEOUT  seconds before a hung fetch is killed (default: 90)
#   WATCH_ONCE           non-empty: one pass, then exit (exit 1 if the fetch failed)
#   WATCH_STATE          file remembering reported branches
#
# Event lines:
#   merged: <branch> -> <base> (<evidence>)
#   ambiguous: <branch> tip is already in <base> with no merge commit ...
#   gone-unconfirmed: <branch> left origin and git finds no evidence of a merge ...
#   no-match: no local branch matches WATCH_PATTERN (once per run)
#   fetch-failed: ... (once per failure streak, at the 3rd failure in a row)
#   fetch-recovered: ... (the fetch works again after a reported failure)
#   bad-config: ... (the watcher cannot run as configured; it exits with code 2)
#
# merged and ambiguous say so when the local branch has commits that are not on origin.
# The base branch itself is never judged, even if the pattern matches it.
#
# An event is a cue to look, not a verdict. See SKILL.md for what git alone cannot tell.

set -u

REPO=${WATCH_REPO:-$PWD}
PATTERN=${WATCH_PATTERN:-'^(fix|feat|feature|refactor|chore)/'}
INTERVAL=${WATCH_INTERVAL:-60}
FETCH_TIMEOUT=${WATCH_FETCH_TIMEOUT:-90}

bad_config() {
  echo "bad-config: $1"
  exit 2
}

cd "$REPO" 2>/dev/null || bad_config "no such directory: $REPO"
REPO=$PWD

BASE=${WATCH_BASE:-$(git symbolic-ref -q --short refs/remotes/origin/HEAD)}
[ -n "$BASE" ] || bad_config "cannot resolve the base branch: set WATCH_BASE, e.g. origin/main"
case "$BASE" in
  origin/?*) ;;
  *) bad_config "WATCH_BASE '$BASE' is not under origin/: only origin is fetched, so it would never move and merges would go unseen" ;;
esac

# grep exits 2 on a broken regex. Left alone, that reads as "no branch matched".
printf 'x\n' | grep -qE -e "$PATTERN" 2>/dev/null
[ "$?" -le 1 ] || bad_config "WATCH_PATTERN '$PATTERN' is not a valid grep -E regex (globs like */123-* are not regexes)"

git patch-id --verbatim </dev/null >/dev/null 2>&1 || bad_config "git patch-id --verbatim is missing: this needs git 2.39 or newer"

# Keyed by the full path: two checkouts with the same directory name must not share state.
STATE=${WATCH_STATE:-${TMPDIR:-/tmp}/merge-watch-$(basename "$REPO")-$(printf '%s' "$REPO" | cksum | cut -d' ' -f1).txt}
touch "$STATE" 2>/dev/null || bad_config "cannot write the state file: $STATE"

# patch-id of each non-merge commit in a range. --verbatim keeps whitespace: the default modes (and
# git cherry) ignore it, and "a  b" versus "a b" is a real difference in many languages.
patch_ids() { # range
  git log -p --no-merges --no-color --no-ext-diff --no-renames "$1" |
    git patch-id --verbatim | cut -d' ' -f1
}

# Prints how the commit reached the base, "ambiguous", or nothing when it did not.
classify() {
  local tip=$1 merge_base path wanted branch_ids
  local paths=()

  if [ "$(git rev-list --count "$BASE..$tip")" -eq 0 ]; then
    # The tip is in the base. A merge commit naming it as a merged parent is proof.
    if git rev-list --merges --parents "$tip..$BASE" |
      awk -v tip="$tip" '{ for (i = 3; i <= NF; i++) if ($i == tip) found = 1 } END { exit !found }'; then
      echo "merge commit"
      return
    fi
    # A fast-forward merge and a pushed branch with no commits of its own look identical.
    echo "ambiguous"
    return
  fi

  # Rebase merge: every commit has an identical patch in the base. Merge commits have no patch here,
  # so a branch holding only a sync merge from the base lists nothing: that is not evidence.
  branch_ids=$(patch_ids "$BASE..$tip")
  if [ -n "$branch_ids" ] &&
    ! printf '%s\n' "$branch_ids" | grep -qvxFf <(patch_ids "$tip..$BASE"; echo no-such-patch-id); then
    echo "same patches"
    return
  fi

  merge_base=$(git merge-base "$BASE" "$tip") || return 0

  # NUL-separated and literal: spaces, quoted non-ASCII names and glob characters must survive.
  # A mangled pathspec matches nothing, the diff comes out empty, and an open branch looks merged.
  while IFS= read -r -d '' path; do
    paths+=("$path")
  done < <(git diff -z --no-renames --name-only "$merge_base" "$tip")

  # Commits that cancel each other out have no contribution to find in the base.
  [ "${#paths[@]}" -eq 0 ] && return 0

  # Squash merge, nothing changed those files since.
  if git --literal-pathspecs diff --quiet --no-renames "$BASE" "$tip" -- "${paths[@]}"; then
    echo "file contents match"
    return
  fi

  # Squash merge, those files changed since: look for one commit carrying the whole branch diff.
  wanted=$(git diff --no-color --no-ext-diff --no-renames "$merge_base" "$tip" | git patch-id --verbatim | cut -d' ' -f1)
  if [ -n "$wanted" ] && patch_ids "$merge_base..$BASE" | grep -qxF "$wanted"; then
    echo "squashed patch"
  fi
}

# A line holds the base too: a branch reported for one base must still be reported for another.
seen() { # branch tip
  grep -qxF "$1 $BASE $2" "$STATE"
}

remember() { # branch tip
  printf '%s %s %s\n' "$1" "$BASE" "$2" >>"$STATE"
}

report() { # branch tip classification
  local ahead keep=
  [ -z "$3" ] && return 1
  # The verdict is about what reached origin. Commits made since then exist only in this branch.
  ahead=$(git rev-list --count "$2..refs/heads/$1")
  [ "$ahead" -gt 0 ] && keep="$ahead local commit(s) are not on origin, keep the branch and review them"
  case "$3" in
    ambiguous)
      echo "ambiguous: $1 tip is already in ${BASE#origin/} with no merge commit (fast-forward merge, or pushed with no commits of its own); check the merge request${keep:+; $keep}"
      ;;
    *)
      echo "merged: $1 -> ${BASE#origin/} ($3); ${keep:-clean up the branch and update the task}"
      ;;
  esac
  remember "$1" "$2"
}

fails=0
announced=

while true; do
  if perl -e 'alarm shift; exec @ARGV' "$FETCH_TIMEOUT" git fetch origin --prune -q 2>/dev/null; then
    [ "$fails" -ge 3 ] && echo "fetch-recovered: fetch in $REPO works again; merges are visible"
    fails=0

    git rev-parse --verify -q "$BASE^{commit}" >/dev/null || bad_config "base ref not found: $BASE"

    # lstrip, not short: short turns a branch into heads/<name> when a tag has the same name.
    branches=$(git for-each-ref --format='%(refname:lstrip=2)' refs/heads | grep -E -e "$PATTERN" | grep -vxF -e "${BASE#origin/}")

    if [ -z "$announced" ]; then
      announced=1
      if [ -z "$branches" ]; then
        echo "no-match: no local branch other than the base matches WATCH_PATTERN '$PATTERN' (a grep -E regex, not a glob); nothing is being watched"
      else
        echo "watching $(printf '%s\n' "$branches" | wc -l | tr -d ' ') branch(es) against $BASE" >&2
      fi
    fi

    while IFS= read -r branch; do
      [ -z "$branch" ] && continue
      local_tip=$(git rev-parse "refs/heads/$branch")
      upstream=$(git for-each-ref --format='%(upstream:short)' "refs/heads/$branch")

      if git show-ref -q --verify "refs/remotes/origin/$branch"; then
        tip=$(git rev-parse "refs/remotes/origin/$branch")
        seen "$branch" "$tip" && continue
        report "$branch" "$tip" "$(classify "$tip")"
      elif [ "$upstream" = "origin/$branch" ]; then
        # It was pushed and is gone from origin: deleted at merge, or closed.
        seen "$branch" "$local_tip" && continue
        if ! report "$branch" "$local_tip" "$(classify "$local_tip")"; then
          # Not "unmerged": commits added after the push and some squashes also end up here.
          echo "gone-unconfirmed: $branch left origin and git finds no evidence of a merge into ${BASE#origin/}; the local branch has $(git rev-list --count "$BASE..$local_tip") commit(s) not reachable from the base: keep the branch and check the merge request"
          remember "$branch" "$local_tip"
        fi
      fi
      # Otherwise it was never pushed: a fresh branch looks exactly like a merged one, so no verdict.
    done <<<"$branches"
  else
    fails=$((fails + 1))
    if [ -n "${WATCH_ONCE:-}" ]; then
      echo "fetch-failed: fetch in $REPO failed; merges are not visible"
      exit 1
    fi
    [ "$fails" -eq 3 ] && echo "fetch-failed: fetch in $REPO failed 3 times in a row; merges are not visible"
  fi

  [ -n "${WATCH_ONCE:-}" ] && break
  sleep "$INTERVAL"
done
