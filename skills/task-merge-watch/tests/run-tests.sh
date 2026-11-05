#!/usr/bin/env bash
# Tests watch-task-branches.sh against throwaway git repositories in a temp directory.
# Usage: bash tests/run-tests.sh
# WATCH_CMD and the *_RE variables let the same scenarios run against another implementation.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
WATCH_CMD=${WATCH_CMD:-"bash $HERE/../watch-task-branches.sh"}
MERGED_RE=${MERGED_RE:-'^merged:'}
GONE_RE=${GONE_RE:-'^gone-unconfirmed:'}
FETCH_RE=${FETCH_RE:-'^fetch-failed:'}

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid

die() { echo "test setup failed: $1" >&2; exit 2; }

PASS=0
FAIL=0
FAILED=()
SEQ=0

# Creates origin, a working clone (W) and a clone acting as the forge's merge button (F).
setup() {
  SEQ=$((SEQ + 1))
  ROOT="$SANDBOX/$SEQ"
  mkdir -p "$ROOT/tmp"
  # One state directory per scenario; only the shared-name scenario below reuses one on purpose.
  export TMPDIR="$ROOT/tmp"
  git init -q --bare -b trunk "$ROOT/origin.git"
  git clone -q "$ROOT/origin.git" "$ROOT/work" 2>/dev/null
  W="$ROOT/work"
  git -C "$W" checkout -q -b trunk 2>/dev/null
  seq 1 40 >"$W/a.txt"
  seq 1 40 >"$W/b.txt"
  git -C "$W" add . && git -C "$W" commit -qm base && git -C "$W" push -q -u origin trunk
  git -C "$W" remote set-head origin trunk
  git clone -q "$ROOT/origin.git" "$ROOT/forge"
  F="$ROOT/forge"
}

branch() { git -C "$W" checkout -q -b "$1" origin/trunk; }
back() { git -C "$W" checkout -q trunk; }

edit() { # file line text
  sed -i.bak "$2s/.*/$3/" "$W/$1" && rm -f "$W/$1.bak"
  git -C "$W" add -A && git -C "$W" commit -qm "edit $1:$2"
}
push() { git -C "$W" push -q -u origin "$1"; }

forge_sync() { git -C "$F" checkout -q trunk && git -C "$F" pull -q; }
forge_merge() { forge_sync; { git -C "$F" merge -q --no-ff -m "merge $1" "origin/$1" && git -C "$F" push -q; } || die "merge $1"; }
forge_squash() { forge_sync; { git -C "$F" merge -q --squash "origin/$1" >/dev/null 2>&1 && git -C "$F" commit -qm "squash $1" && git -C "$F" push -q; } || die "squash $1"; }
forge_rebase() {
  forge_sync
  { git -C "$F" checkout -q -B tmp "origin/$1" && git -C "$F" rebase -q trunk >/dev/null &&
    git -C "$F" checkout -q trunk && git -C "$F" merge -q --ff-only tmp && git -C "$F" push -q; } || die "rebase $1"
}
forge_edit() { # file line text
  forge_sync
  sed -i.bak "$2s/.*/$3/" "$F/$1" && rm -f "$F/$1.bak"
  { git -C "$F" add -A && git -C "$F" commit -qm "forge edit" && git -C "$F" push -q; } || die "forge edit"
}
forge_delete() { git -C "$F" push -q origin --delete "$1"; }

watch_once() { # extra args as env assignments
  env WATCH_REPO="$W" WATCH_BASE=origin/trunk WATCH_ONCE=1 "$@" $WATCH_CMD 2>"$ROOT/stderr"
}

ok() { PASS=$((PASS + 1)); echo "  ok    $1"; }
bad() { FAIL=$((FAIL + 1)); FAILED+=("$1"); echo "  FAIL  $1"; [ -n "${2:-}" ] && printf '        output: %s\n' "$2"; }

expect() { # name regex
  local out; out=$(watch_once)
  if printf '%s\n' "$out" | grep -qE "$2"; then ok "$1"; else bad "$1" "$out"; fi
}
expect_silent() { # name
  local out; out=$(watch_once)
  if [ -z "$out" ]; then ok "$1"; else bad "$1" "$out"; fi
}
expect_not() { # name regex
  local out; out=$(watch_once)
  if printf '%s\n' "$out" | grep -qE "$2"; then bad "$1" "$out"; else ok "$1"; fi
}

echo "merged branches are noticed"

setup; branch fix/101-x; edit a.txt 5 one; push fix/101-x; back
forge_merge fix/101-x
expect "merge commit" "$MERGED_RE"

setup; branch fix/101-x; edit a.txt 5 one; edit a.txt 25 two; push fix/101-x; back
forge_squash fix/101-x
expect "squash of two commits" "$MERGED_RE"

setup; branch fix/101-x; edit a.txt 5 one; edit a.txt 25 two; push fix/101-x; back
forge_squash fix/101-x; forge_edit a.txt 5 later
expect "squash, then the same file changes again" "$MERGED_RE"

setup; branch fix/101-x; edit a.txt 5 one; edit a.txt 25 two; push fix/101-x; back
forge_edit b.txt 1 unrelated; forge_rebase fix/101-x; forge_edit a.txt 5 later
expect "rebase merge, then the same file changes again" "$MERGED_RE"

setup; branch fix/101-x; edit a.txt 5 one; push fix/101-x; back
forge_squash fix/101-x; forge_delete fix/101-x
expect "branch deleted on origin after a merge" "$MERGED_RE"

setup; branch fix/101-x; edit a.txt 5 one; push fix/101-x; back
forge_edit a.txt 35 far; forge_squash fix/101-x
expect "squash over a distant edit in the same file" "$MERGED_RE"

setup; branch "fix/101-x"; echo new >"$W/my file.txt"; git -C "$W" add -A; git -C "$W" commit -qm spaces; push fix/101-x; back
forge_squash fix/101-x
expect "squash touching a filename with spaces" "$MERGED_RE"

echo "open branches stay quiet"

setup; branch fix/101-x; back
expect_silent "fresh unpushed branch"

setup; branch fix/101-x; edit a.txt 5 one; back
expect_silent "unpushed branch with commits"

setup; branch fix/101-x; edit a.txt 5 one; push fix/101-x; back
expect_silent "pushed and not merged"

setup; branch fix/101-x; push fix/101-x; back
expect_not "pushed with no commits of its own is not called merged" "$MERGED_RE"

setup; branch fix/101-x; echo new >"$W/my file.txt"; git -C "$W" add -A; git -C "$W" commit -qm spaces; push fix/101-x; back
expect_silent "open branch touching a filename with spaces"

setup; branch fix/101-x; echo new >"$W/файл.txt"; git -C "$W" add -A; git -C "$W" commit -qm cyr; push fix/101-x; back
expect_silent "open branch touching a non-ASCII filename"

setup; branch fix/101-x; echo new >"$W/[draft]*.txt"; git -C "$W" add -A; git -C "$W" commit -qm glob; push fix/101-x; back
expect_silent "open branch touching a filename with glob characters"

setup; branch fix/101-x; edit a.txt 5 one; edit a.txt 5 5; push fix/101-x; back
expect_silent "commits that cancel each other out"

setup; branch fix/101-x; forge_edit b.txt 1 unrelated; git -C "$W" fetch -q; git -C "$W" merge -q --no-ff --no-edit origin/trunk; push fix/101-x; back
expect_silent "open branch with only a sync merge from the base"

setup; branch fix/101-x; edit a.txt 5 one; forge_edit b.txt 1 unrelated; git -C "$W" fetch -q; git -C "$W" merge -q --no-ff --no-edit origin/trunk; push fix/101-x; back
expect_silent "open branch with its own commit and a sync merge"

setup; branch fix/101-x; edit a.txt 5 'a  b'; push fix/101-x; back
forge_edit a.txt 5 'a b'
expect_silent "open branch differing from a base commit only in whitespace"

setup; branch fix/101-x; edit a.txt 5 'a  b'; edit a.txt 25 'c  d'; push fix/101-x; back
forge_sync
sed -i.bak -e '5s/.*/a b/' -e '25s/.*/c d/' "$F/a.txt" && rm -f "$F/a.txt.bak"
{ git -C "$F" add -A && git -C "$F" commit -qm "one commit, other whitespace" && git -C "$F" push -q; } || die "whitespace commit"
expect_silent "open branch whose whole diff differs from one base commit only in whitespace"

setup; git -C "$W" checkout -q -b feature/big origin/trunk; push feature/big; edit a.txt 5 one; push feature/big; back
out=$(watch_once WATCH_BASE=origin/feature/big WATCH_PATTERN='^feature/')
if printf '%s\n' "$out" | grep -qE '^(merged|ambiguous):'; then bad "the base branch is not judged against itself" "$out"; else ok "the base branch is not judged against itself"; fi

echo "local work is not called disposable"

setup; branch fix/101-x; edit a.txt 5 one; push fix/101-x; edit a.txt 25 unpushed; back
forge_merge fix/101-x
out=$(watch_once)
if printf '%s\n' "$out" | grep -qE "$MERGED_RE" && printf '%s\n' "$out" | grep -q 'not on origin' && ! printf '%s\n' "$out" | grep -qi 'clean up'; then
  ok "merged with local commits ahead: flagged, no cleanup cue"
else
  bad "merged with local commits ahead: flagged, no cleanup cue" "$out"
fi

setup; branch fix/101-x; push fix/101-x; edit a.txt 25 unpushed; back
out=$(watch_once)
if printf '%s\n' "$out" | grep -q 'not on origin'; then ok "ambiguous with local commits ahead: flagged"; else bad "ambiguous with local commits ahead: flagged" "$out"; fi

setup; branch fix/101-x; edit a.txt 5 one; push fix/101-x; back
forge_merge fix/101-x
out=$(watch_once)
if printf '%s\n' "$out" | grep -q 'clean up' && ! printf '%s\n' "$out" | grep -q 'not on origin'; then ok "merged with nothing local: cleanup cue stays"; else bad "merged with nothing local: cleanup cue stays" "$out"; fi

echo "closed without merging"

setup; branch fix/101-x; edit a.txt 5 one; push fix/101-x; back
forge_delete fix/101-x
expect "closed, branch deleted on origin" "$GONE_RE"

setup; branch fix/101-x; edit a.txt 5 one; push fix/101-x; edit a.txt 25 unpushed; back
forge_merge fix/101-x; forge_delete fix/101-x
out=$(watch_once)
if printf '%s\n' "$out" | grep -qE "$GONE_RE" && printf '%s\n' "$out" | grep -qE '[0-9]+ commit' && ! printf '%s\n' "$out" | grep -qiE 'are not in|clean up'; then
  ok "merged, deleted, then a local commit: no false claim, commits surfaced"
else
  bad "merged, deleted, then a local commit: no false claim, commits surfaced" "$out"
fi

setup; branch fix/101-x; edit a.txt 5 one; push fix/101-x; back
forge_edit a.txt 7 neighbor; forge_squash fix/101-x; forge_delete fix/101-x
out=$(watch_once)
if printf '%s\n' "$out" | grep -qE "$GONE_RE" && ! printf '%s\n' "$out" | grep -qi 'are not in'; then ok "undetectable squash, deleted: does not claim the changes are absent"; else bad "undetectable squash, deleted: does not claim the changes are absent" "$out"; fi

echo "state"

setup; branch fix/101-x; edit a.txt 5 one; push fix/101-x; back
forge_merge fix/101-x; watch_once >/dev/null
expect_silent "second pass does not repeat an event"

setup; branch fix/101-x; edit a.txt 5 one; push fix/101-x; back
forge_merge fix/101-x; watch_once >/dev/null
FIRST_W=$W
SEQ=$((SEQ + 1)); ROOT="$SANDBOX/$SEQ"; mkdir -p "$ROOT"  # same TMPDIR as the first checkout
git init -q --bare -b trunk "$ROOT/origin.git"; git clone -q "$ROOT/origin.git" "$ROOT/other" 2>/dev/null
mkdir -p "$ROOT/same"; git clone -q "$ROOT/origin.git" "$ROOT/same/work" 2>/dev/null
W="$ROOT/same/work"; git -C "$W" checkout -q -b trunk 2>/dev/null
seq 1 40 >"$W/a.txt"; git -C "$W" add .; git -C "$W" commit -qm base; git -C "$W" push -q -u origin trunk
git clone -q "$ROOT/origin.git" "$ROOT/forge"; F="$ROOT/forge"
branch fix/101-x; edit a.txt 5 one; push fix/101-x; back
forge_merge fix/101-x
expect "two checkouts with one directory name do not share state ($(basename "$FIRST_W"))" "$MERGED_RE"

setup; forge_sync; git -C "$F" checkout -q -b rc1; git -C "$F" push -q -u origin rc1; git -C "$F" checkout -q trunk
branch fix/101-x; edit a.txt 5 one; push fix/101-x; back
git -C "$F" checkout -q rc1; git -C "$F" pull -q; git -C "$F" merge -q --no-ff -m "into rc1" origin/fix/101-x; git -C "$F" push -q; git -C "$F" checkout -q trunk
watch_once WATCH_BASE=origin/rc1 >/dev/null
forge_merge fix/101-x
expect "a merge into a second base is still reported" "$MERGED_RE"

setup; branch fix/101-x; edit a.txt 5 one; push fix/101-x; back
git -C "$W" tag fix/101-x
forge_merge fix/101-x
expect "a tag named like the branch does not hide it" "$MERGED_RE"

echo "failures are loud"

setup; branch fix/101-x; edit a.txt 5 one; push fix/101-x; back
git -C "$W" remote set-url origin "$ROOT/nonexistent.git"
out=$(perl -e 'alarm shift; exec @ARGV' 8 env WATCH_REPO="$W" WATCH_BASE=origin/trunk WATCH_INTERVAL=0 $WATCH_CMD 2>/dev/null)
if printf '%s\n' "$out" | grep -qE "$FETCH_RE"; then ok "looping: repeated fetch failure is reported"; else bad "looping: repeated fetch failure is reported" "$out"; fi

setup; branch fix/101-x; edit a.txt 5 one; push fix/101-x; back
git -C "$W" remote set-url origin "$ROOT/nonexistent.git"
out=$(watch_once); code=$?
if printf '%s\n' "$out" | grep -qE "$FETCH_RE" && [ "$code" -ne 0 ]; then ok "single pass: fetch failure is reported"; else bad "single pass: fetch failure is reported" "code=$code out=$out"; fi

setup; branch fix/101-x; edit a.txt 5 one; push fix/101-x; back
out=$(watch_once WATCH_PATTERN='^nothing/')
if printf '%s\n' "$out" | grep -q '^no-match:'; then ok "a pattern matching nothing is an event on stdout"; else bad "a pattern matching nothing is an event on stdout" "stdout: $out"; fi

setup; branch fix/101-x; edit a.txt 5 one; push fix/101-x; back
out=$(watch_once WATCH_PATTERN='*/101-*')
if printf '%s\n' "$out" | grep -qE '^(no-match|bad-config):'; then ok "a glob as the pattern is an event on stdout"; else bad "a glob as the pattern is an event on stdout" "stdout: $out"; fi

setup; branch fix/101-x; edit a.txt 5 one; push fix/101-x; back
out=$(watch_once WATCH_PATTERN='('); code=$?
if printf '%s\n' "$out" | grep -q '^bad-config:' && [ "$code" -ne 0 ]; then ok "an invalid regex is an event on stdout"; else bad "an invalid regex is an event on stdout" "code=$code stdout: $out"; fi

setup; branch fix/101-x; edit a.txt 5 one; push fix/101-x; back
out=$(watch_once WATCH_BASE=origin/nope); code=$?
if printf '%s\n' "$out" | grep -q '^bad-config:' && [ "$code" -ne 0 ]; then ok "a base that does not exist is an event on stdout"; else bad "a base that does not exist is an event on stdout" "code=$code stdout: $out"; fi

setup; branch fix/101-x; edit a.txt 5 one; push fix/101-x; back
git -C "$W" remote add upstream "$ROOT/origin.git"; git -C "$W" fetch -q upstream
out=$(watch_once WATCH_BASE=upstream/trunk); code=$?
if printf '%s\n' "$out" | grep -q '^bad-config:' && [ "$code" -ne 0 ]; then ok "a base on another remote is refused: the fetch would not update it"; else bad "a base on another remote is refused: the fetch would not update it" "code=$code stdout: $out"; fi

setup; branch fix/101-x; edit a.txt 5 one; push fix/101-x; back
out=$(watch_once WATCH_BASE=trunk); code=$?
if printf '%s\n' "$out" | grep -q '^bad-config:' && [ "$code" -ne 0 ]; then ok "a local base is refused: the fetch would not update it"; else bad "a local base is refused: the fetch would not update it" "code=$code stdout: $out"; fi

setup; branch fix/101-x; edit a.txt 5 one; push fix/101-x; back
GOOD_URL=$(git -C "$W" remote get-url origin)
git -C "$W" remote set-url origin "$ROOT/nonexistent.git"
LOOP_OUT="$ROOT/loop.out"
env WATCH_REPO="$W" WATCH_BASE=origin/trunk WATCH_INTERVAL=0 $WATCH_CMD >"$LOOP_OUT" 2>/dev/null &
LOOP_PID=$!
wait_for() { # regex
  local tries=0
  while [ "$tries" -lt 150 ]; do
    grep -qE "$1" "$LOOP_OUT" && return 0
    perl -e 'select(undef, undef, undef, 0.1)'
    tries=$((tries + 1))
  done
  return 1
}
if wait_for "$FETCH_RE"; then
  git -C "$W" remote set-url origin "$GOOD_URL"
  if wait_for '^fetch-recovered:'; then ok "recovery after a reported fetch failure is an event"; else bad "recovery after a reported fetch failure is an event" "$(cat "$LOOP_OUT")"; fi
else
  bad "recovery after a reported fetch failure is an event" "no fetch failure seen: $(cat "$LOOP_OUT")"
fi
kill "$LOOP_PID" 2>/dev/null
wait "$LOOP_PID" 2>/dev/null

echo "known limits, pinned so a change in behavior is visible"

setup; branch fix/101-x; edit a.txt 5 one; push fix/101-x; back
expect_silent "LIMIT closed, branch kept on origin: git has no signal"

setup; branch fix/101-x; edit a.txt 5 one; push fix/101-x; back
forge_edit a.txt 7 neighbor; forge_squash fix/101-x; forge_edit a.txt 5 later
expect_silent "LIMIT squash over changed context, then the file changes again: missed"

setup; branch fix/101-x; edit a.txt 5 one; push fix/101-x; back
forge_edit a.txt 7 neighbor; forge_squash fix/101-x
expect_silent "LIMIT squash over a neighboring edit: missed even if nothing changes later"

setup; branch fix/101-x; edit a.txt 5 one; push fix/101-x; back
forge_edit a.txt 7 neighbor; forge_rebase fix/101-x
expect_silent "LIMIT rebase over a neighboring edit: missed"

setup; branch fix/101-x; edit a.txt 5 same; push fix/101-x; back
forge_edit a.txt 5 same
expect "LIMIT same content landed independently: reported as merged" "$MERGED_RE"

setup; branch fix/101-x; edit a.txt 5 one; git -C "$W" push -q origin fix/101-x; back
forge_merge fix/101-x; forge_delete fix/101-x
expect_silent "LIMIT pushed without an upstream, deleted on origin: looks never pushed"

setup; git -C "$F" checkout -q -b rc1; seq 1 3 >"$F/rc.txt"; git -C "$F" add -A; git -C "$F" commit -qm rc; git -C "$F" push -q -u origin rc1
git -C "$F" checkout -q trunk; git -C "$F" merge -q --no-ff -m "rc into trunk" rc1; git -C "$F" push -q
git -C "$W" fetch -q; git -C "$W" checkout -q -b fix/101-x origin/rc1; push fix/101-x; back
expect "LIMIT fresh branch on a merged tip: identical to a real merge" "$MERGED_RE"

echo
echo "passed: $PASS, failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'failed: %s\n' "${FAILED[@]}"
  exit 1
fi
