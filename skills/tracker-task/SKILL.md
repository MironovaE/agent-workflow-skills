---
name: tracker-task
description: Create a task in a web issue tracker before the work and fill it in afterwards with what was done and how to check it, working through the user's logged-in browser tab. Works with any tracker that has a web UI. Use when the user says "create a task", "file a ticket", "fill in the task with the results", "write up the card", finishes a change and needs the card filled, or wants a handoff in the team's card format. Also triggers on "заведи задачу", "заполни задачу по результатам", "оформи задачу".
---

# Tracker task: create it, then fill it from the facts

A task card is read by the person who checks the work, not by the person who did it. They need to
know what they will see and how to confirm it. This skill writes that card from real facts and
never changes anything in the tracker without an explicit yes.

## Project settings

Fill these in for your team, in the repository's agent instructions or a local copy of this skill:

| Setting | Example |
| --- | --- |
| Tracker URL | `<https://tracker.example.com>` |
| Environment for manual checks | `<https://test.example.com>` |
| Environments that must not appear in check steps | `<production URL>` |
| Card format | The template below, or your own |

If a setting is missing, ask for it. Do not guess which tracker or environment to use.

## 1. Work through the logged-in tab

Use the browser tab where the user is already logged in. The agent acts inside that session, so
actions in the tracker are made as the user.

- **Login is the user's job.** Never ask for a password or token in chat and never type one into a
  form. If the session has expired, say so and ask the user to log in.
- **Credentials stay in the browser.** Do not print, copy or save session tokens or cookies, and do
  not move them to a script or `curl`. Requests are made from the page itself.
- **A failed request may be a network problem.** If the tracker is on a private network, a failed
  fetch or an unresolved host can mean the VPN is down or the session expired. Check that before
  debugging anything else.

## 2. Discover the API; do not guess it

Open the relevant tracker screen and read the requests the page itself makes. They show the real
paths, fields and header names. Record names only: never print the values of authorization headers,
cookies or tokens from the traffic.

1. Find the requests behind the task list, opening a card and saving a card.
2. Take field names from the actual requests and responses.
3. If a path is not in the page's traffic, trigger the matching action in the UI or ask the user.
   Trying paths by pattern gives misleading errors, and a write to a guessed path can have side
   effects.

If the tracker offers no usable API from the page, use the UI directly. Everything else in this
skill still applies.

## 3. Read before writing

Before any change, read the card's current state:

- title, description, status and assignee;
- comments and attachments, when they affect the task;
- who created the card, and whether someone else has written in it.

**Do not overwrite someone else's text.** Saving a description often replaces it whole. If another
person wrote the card, keep their text in the new version, for example under "Original
description:", and change only what you were asked to change. Do not edit other people's comments.

Do not change a status from memory: it may have moved since you last read it. If the card is
already with a reviewer or closed, tell the user instead of changing it.

## 4. Collect the facts

- Take the affected areas from the real diff (`git diff --name-only`), not from memory.
- Open the check locations and confirm they exist. Use direct links.
- Use concrete test values, exact error texts and expected UI states.
- Describe only what the change really touches. Do not invent screens or steps because they seem
  likely.

For backend or tooling work, a "screen" can be an endpoint, a log line or an admin page. The check
steps are still required: they describe what the checker observes, not which file changed.

## 5. Dry run, then an explicit yes

Show the user the exact write before making it:

```text
Tracker:  <tracker URL>
Action:   create | update card <id>
Title:    <exact text>
Description:
<exact text>
Other fields: <assignee, priority, status — only those being set>
```

Then wait for an explicit yes **to this text**. Approval of an earlier version or a different card
does not count. If the text changes, show it again.

## 6. Write it

- **A 403 on a write may be a missing CSRF header, not missing rights.** Reads can pass on the
  session alone while writes need a CSRF token. See how the page's own save request sends it and
  do the same from within the page. Use the token only in that request: do not print, save or move
  it out of the page. Only then conclude that the user lacks permission.
- Send every field your tracker needs explicitly. A field left out may be stored empty and make the
  card disappear from filtered views. Check which fields the page's own create request sends.
- Prefer one save action. Do not retry a failed create until you have checked that no card was
  created.

## 7. Read it back

**A successful response does not prove the write worked.** An API can answer 200 and silently ignore
a field it does not accept, such as an assignee sent in the wrong shape. So:

1. Open the card again, or fetch it again.
2. Compare the title, description, assignee and status with what you showed the user.
3. Check that line breaks and formatting render correctly.
4. If a field did not change, compare your payload with the page's own request and fix it.

Report the card's number and link only after this check.

## Card format

Replace this with your team's format. If you have none, this works well:

```text
Title
<one short line about the result for the user>

Description
What was done:
<2–5 short points about the actual changes>

Where to check:
<screen or area> — <direct link to the check environment>

How to check <scenario>:
1. <a concrete action, with a test value>
2. <the expected, observable result>
```

Content rules:

- "How to check" is required, even when the user asks for something brief.
- List the 2–4 places really affected, not every section of the product.
- Use a separate "How to check" block for each scenario or field type.
- If the change is not deployed yet, say so: "check after deployment to `<environment>`".
- Never send the checker to production to test a fix.
- Leave out linters, type checks and test counts: they tell the checker nothing about what to see.
- Follow your team's convention on merge request links. Many keep them out of the card.
- If the tracker numbers cards itself, do not repeat the number in the title.

## Do not

- Do not write to the tracker without an explicit yes to this exact text.
- Do not invent screens, steps, results or test values.
- Do not ask for, read or move credentials.
- Do not test a fix or create test data in production.
- Do not call a card done on the strength of a successful response alone.

## Related skills

- `tracker-visual-evidence` adds before/after screenshots to a card.
- `refactor-log` records the work for your own reporting. The card is for the checker; the log is
  for you.
