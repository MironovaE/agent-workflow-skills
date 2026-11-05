---
name: work-report
description: Report on work done over a period. First reconcile the work log against git, then produce a dense report with verified numbers (lines removed, defects found, test coverage), in a technical or a business version. Use when the user says "make a report for this period", "what was done this week / month", "a more detailed report", "a report for the business / management / the client", "no technical terms", "plain language", "is everything in the log", "reconcile the log with git", prepares for a review or shows results to others, or «сделай отчёт за период», «что сделано за неделю», «отчёт для бизнеса», «человеческим языком», «сверь журнал с git».
---

# Report on work done over a period

Why: to show what was done and what it changed, clearly and with numbers that can be checked, for a
manager, for a review, for yourself. The report is built **from the log** (see `refactor-log`) and from
the archives if the window reaches them. So reconciliation comes first: what isn't in the log won't be in
the report.

Two phases in a fixed order: **reconcile → report**. Don't start the report until you've reported the gaps.

Two report modes, sharing the reconciliation and the numbers:

- **Technical** (default): phase 3, for engineering and reviews.
- **Business**: phase 3B, when asked for "business", "management" or "no technical terms". If both are
  requested, give both, business first.

Difference from `refactor-log`: that skill **keeps** the log (appends entries, closes periods). This one
**reads** it and builds a report for an arbitrary window. Gaps found in phase 1 are closed through
`refactor-log`; don't duplicate its entry format here.

---

## Phase 0: frame

- The date window. If it isn't given, ask in one line. Take "today" from `date +%F` and convert relative
  dates to absolute ones.
- The repositories the log spans. List them explicitly; one log may cover several products.
- Personal projects don't go into a work report.

---

## Phase 1: reconcile (is everything recorded?)

### 1.1 Collect the author's commits for the window

Traps where data gets lost. Avoid them from the start:

- **`--since` / `--until` filter by COMMITTER date, while `%ad` is the author date.** After a rebase they
  can differ by days, so a commit authored inside the window can fall outside `--since`. Use a wide
  `--since` and filter by `%ad` with `awk`.
- **zsh does not split `$list` into words.** `for c in $list` passes the whole list as one argument and
  git fails with `unknown revision`. Use `while read -r c` or `${=list}`.
- **Merge commits may have a different author name.** Check how the author appears in the history. Use
  `--no-merges --author=<name>`, or the volume doubles.
- **`--all` counts rebased commits twice.** After a rebase the graph holds both copies, with different
  hashes but the same author timestamp and subject. Counts and +/- totals inflate silently. Deduplicate on
  the pair `%at` + `%s`, as below. Subject alone is not enough: it would merge different commits that share
  a message such as "fix lint". A rebase that resets the author date (`--ignore-date`, `--reset-author`)
  leaves both copies in, so look through repeated subjects in the result by eye.
- **`--all` also picks up unmerged branches.** That's work done but not delivered: you may count it, but
  you may not hide the difference. Check each commit with `merge-base --is-ancestor ... origin/<base>` and
  name unmerged work on a separate line, not inside the total.

Shell variables may not survive between tool calls, so each block below sets its own and finds the window
through a file named after the repository and dates. Use the same `REPO`, `FROM` and `TO` in all of them. A
block that can't find its window stops with an error instead of counting zero.

```bash
REPO=path/to/repo; FROM=YYYY-MM-DD; TO=YYYY-MM-DD; AUTHOR='Your Name'
WINDOW="${TMPDIR:-/tmp}/work-report-$(basename "$REPO")-$FROM-$TO.tsv"
# columns: hash, author date, author timestamp, subject
git -C "$REPO" log --all --no-merges --author="$AUTHOR" --since="$FROM -30 days" \
    --pretty='%h%x09%ad%x09%at%x09%s' --date=short \
  | awk -F'\t' -v a="$FROM" -v b="$TO" '$2>=a && $2<=b && !seen[$3 FS $4]++' > "$WINDOW"
wc -l < "$WINDOW"
```

### 1.2 Extract task numbers and check the logs

```bash
(
  REPO=path/to/repo; FROM=YYYY-MM-DD; TO=YYYY-MM-DD
  TASK_PATTERN='<task-number-regex>'               # such as '#[0-9]+'
  LOG_DIR=${LOG_DIR:-work-log}                     # same default as refactor-log
  WINDOW="${TMPDIR:-/tmp}/work-report-$(basename "$REPO")-$FROM-$TO.tsv"
  [ -f "$WINDOW" ] || { echo "no window file $WINDOW: run 1.1 first" >&2; exit 1; }
  : "${TASK_PATTERN:?set TASK_PATTERN to the regex of your task numbers, such as '#[0-9]+'}"
  set -- "$LOG_DIR"/LOG*.md
  [ -f "$1" ] || { echo "no log files in $LOG_DIR" >&2; exit 1; }
  numbers=$(cut -f4 "$WINDOW" | grep -oE "$TASK_PATTERN" | sort -u)
  [ -n "$numbers" ] || { echo "no task numbers found: check TASK_PATTERN and the window" >&2; exit 1; }
  printf '%s\n' "$numbers" | while read -r n; do
    printf '%s log:%s\n' "$n" "$(cat "$@" | grep -Fwc -- "$n")"   # whole word: #123 is not #1234
  done
)
```

If you keep more than one journal (for example, achievements and a technical record of reviewed files),
check **all of them**: they answer different questions, and one doesn't replace another.

Don't list commits without a task number (branch syncs, formatting) as gaps right away. First search the
log for their subject.

### 1.3 Check status and freshness

- Merged? `git merge-base --is-ancestor <hash> origin/<base> && echo MERGED`
- Merge commit: `git log origin/<base> --ancestry-path --merges --pretty='%h %s' <hash>..origin/<base> | tail -1`
- **Stale statuses in the log itself.** Search the window's entries for "in review", "not merged" or "MR
  open" and compare with git. An entry that says "in review" is wrong if the branch has already landed.
  Fix the wording and add the merge hashes.

### 1.4 Report the gaps and stop

Show a compact table: `what | tasks | status in git`. Then **ask** whether to add them, through
`refactor-log` and not in your own format.

A report from an incomplete log may go out only with an explicit note of what's missing. Silently counting
from a log with holes is not allowed: the numbers come out wrong.

---

## Phase 2: numbers

Count from git, don't retell the log from memory. Every number in the report comes either from an entry's
`Stats:` line or from the command below.

```bash
# unique files and total +/- for all commits in the window
(
  REPO=path/to/repo; FROM=YYYY-MM-DD; TO=YYYY-MM-DD
  WINDOW="${TMPDIR:-/tmp}/work-report-$(basename "$REPO")-$FROM-$TO.tsv"   # the deduplicated window from 1.1
  [ -s "$WINDOW" ] || { echo "window $WINDOW is missing or empty: run 1.1 first" >&2; exit 1; }
  add=0; del=0; cnt=0; tmp=$(mktemp); commits=$(mktemp)
  cut -f1 "$WINDOW" > "$commits"
  while read -r c; do
    s=$(git -C "$REPO" show --shortstat --format= "$c") || { echo "cannot read commit $c in $REPO" >&2; exit 1; }
    a=$(echo "$s" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+')
    d=$(echo "$s" | grep -oE '[0-9]+ deletion'  | grep -oE '[0-9]+')
    add=$((add+${a:-0})); del=$((del+${d:-0})); cnt=$((cnt+1))
    git -C "$REPO" show --name-only --pretty=format: "$c" >> "$tmp"
  done < "$commits"
  echo "commits $cnt, unique files $(sort -u "$tmp" | grep -c .), +$add / -$del"
  rm -f "$tmp" "$commits"
)
```

**What to measure.** Use the metrics that apply and can be verified. Each shows one thing and can mislead,
so report it within its limit:

| Metric | Source | What it shows | What it doesn't show |
|---|---|---|---|
| **Net line change** (`add - del`) | total over the window | whether the code grew or shrank | value: fewer lines isn't automatically better |
| **Defects found and fixed** | entry bullets | real problems closed; give the breakdown: during audit / as separate tasks / by product | how severe they were, unless you say so |
| **Tests, before → after** | `Stats:` lines | how many checks were added | how much of the behavior they cover |
| **Dependencies removed** | cleanup entries | a smaller surface to maintain | any effect on users |
| **Measured bundle size** | entries | `before → after KB gzip`, a real measurement | speed for the user, unless measured too |
| **Files touched** (unique) | git | how widely the change reached | how hard or useful it was |

Counting rules:

- **Unique files, not a sum across commits.** One file in three commits would otherwise triple the scale,
  and the number becomes a lie.
- Count defects one by one from the log and **state the breakdown**, so a reader can check the total.
- Don't sum metrics from different products into one line. Each gets its own.

---

## Phase 3: report format

The title is just the date range. Then numbered blocks, **one block per line of work, not per task**:
around 5–7 for a week, or the report falls apart into a ticket list.

```
# <from> to <to>

**1. 🏆 <Result in one phrase> (<dates>).** <A dense paragraph: what exactly, task numbers,
and the verified numbers that apply: files, lines, packages, measured size.>

**2. <Result> (<dates>).** <The same. Inside the block, the most striking detail: a defect found
along the way, an unexpected finding. One such detail per block, not a list.>

...

---

**Total:** <per product: N commits, N files, -N lines>.
Tests N → N. **N defects found and fixed.**

Just outside the window (<date>): 🏆 <work adjacent to the window's edge>.
```

What makes a report clear and trustworthy:

- **Each block leads with the result, not the process.** "Legacy stack fully removed", not "work on
  removing the legacy stack".
- **🏆 only on achievements:** new functionality delivered end to end, or a qualitative shift. Ordinary
  cleanup gets no mark, or the mark loses its value.
- **A verified number wherever the work has one.** Don't add a number just to fill a block.
- **Benefit before volume.** If a refactor uncovered a live defect, say that first: it tells the reader more
  than how many props were removed.
- **"Before → after" wherever there's a measurement.**
- **Short lines.** No kilometer-long paragraphs, and only compact tables.
- Don't retell "Decisions and why" from the log. One least obvious finding per block goes in the report.

**Loose ends in a separate final block**, if any: unmerged branches, journals not updated, an out-of-date
local base. Leaving them out would make the rest of the report harder to trust.

---

## Phase 3B: business report

The reader doesn't know how the system is built and is deciding what the work is worth. They must
understand without translation: what works now, who benefits, what won't happen anymore. The facts are the
same as in the technical report; the language and what comes first change. Show log gaps and internal loose
ends to the author in chat **before** the report; they don't go into the business text.

```
# Results of the work: <from> to <to>

<The main point: 2–3 sentences on what changed for the organization's work.>

**1. <Result for people in one phrase>.** <Before → after, who feels it, a number if measured.>

**2. <Result>.** <The same.>

...

**In progress:** <what's ready and awaiting release, and what users get after it>.

**Total:** N tasks completed, N ready and awaiting release.
```

**What keeps it clear without technical words:**

- **A business tone.** A block title is a finished result: "Password reset emails now arrive within a minute". No
  icons, jokes, slang or excuses.
- **The consequence, not the mechanism.** Not how it was fixed, but what was wrong for the person and what
  happens now: "An expired coupon stopped checkout with no explanation → the page now says why it can't be used."
- **Before → after, with a number where one was measured.** Use numbers that make sense without context: seconds of
  waiting, number of scenarios, screens, devices checked. Don't mention lines of code, files, commits or
  tests: they don't mean value to this reader.
- **Scale through coverage.** "On all tablet sizes", "in every list", if confirmed.
- **Group by value:** new capabilities → speed and reliability → data protection → convenience. Around 3–6
  blocks for a week; combine tasks, don't list them.
- **Don't hide or inflate internal work.** Linters, docs and library upgrades get one sentence on what it
  means: "System components were updated to current versions with the vendors' fixes", if that's what happened.

**Translating terms.** Don't swap words mechanically; name the meaning. Build this table for your own product:

| Instead of | Write |
|---|---|
| internal product names and nicknames | what the thing is for the reader |
| defect, bug | error, malfunction |
| 504, timeout, crash | didn't open, ended with an error |
| masking, redaction | secrets stay out of the logs |
| roles, 403 | access is limited to the people who need it |
| rate limit | the service keeps working during traffic spikes |
| lazy loading, bundle size | pages load faster (only if measured) |
| deploy, merge, MR, branch | release, ready for release |
| domain abbreviations | the full name as the reader knows it; an abbreviation the product itself shows may stay |

**Honesty beats polish:**

- **Done ≠ delivered.** Unmerged and unreleased work goes only under "In progress", worded "ready, awaiting
  release", with its own line in the total. Merged to a shared branch but not in production: say "handed over
  for verification" or "available after release" unless production is confirmed.
- **Don't imagine benefits.** "Saves N hours", "reduces risk by N%" or "increases efficiency" only with a
  measurement. No measurement: name the observable change.
- **Describe vulnerabilities by substance, with no way to reproduce them:** what's protected now, not how it
  could be bypassed. Don't exaggerate: "closed the possibility", not "prevented a leak", if there was no leak.
- **No value for this reader, no inclusion.** Four solid blocks beat seven stretched ones.

**Check before handing it over.** The text contains none of: task or MR numbers, hashes, library names and
versions, file or endpoint names, response codes, English technical terms if the reader's language differs,
team nicknames, or empty bureaucratic phrases ("work was carried out on", "the process was optimized"). Every
number traces to the log or git, as in technical mode.

---

## Rules

- Don't change the phase order: reconcile → gaps shown → report. A report first is a report on who knows what.
- No number from memory. If you can't confirm it, don't write it.
- Log entries are added by `refactor-log`, not this skill.
- Don't commit the log directory.
- The report goes to chat by default; to a file or a published page only on explicit request.
