---
name: backend-drift
description: 'Compare a frontend screen with what the backend actually returns, find where the data chain breaks, and split the findings into "fix on our side" and "question for the backend team". Use when the user says "why is this column empty", "the field doesn''t fill in", "check against the backend", "does the endpoint return this", "is it frontend or backend", "write up a question for the backend", pastes a defect about missing data, or when a screen renders fields the API never returns. Russian triggers: "почему колонка пустая", "поле не заполняется", "сверь с бэком", "проверь, отдаёт ли ручка", "фронт или бэк", "оформи вопрос к бэку".'
---

# Backend drift

Goal: starting from a screen or a defect report, find **exactly where the chain breaks**:

**database column → entity → response DTO → frontend type → rendering**

The result is two lists: fixes the frontend can make itself, and questions for the backend team.

All examples below are invented for illustration. Replace them with what you find in your project.

## The boundary is the main rule

Our part is exactly four things: **find the fault, describe what, how and why, ask the questions, and link the screen.**

- If it is 100% clear and fixable on the frontend, **fix it** and leave it out of the questions file.
- If it is unclear or belongs to the backend, **add one row to the questions file** and let the backend team work it out.
- **Do not write a step-by-step plan through their files.** "Add this field to that DTO, then this mapper line" does their job and rests on our reconstruction of their code, which may be wrong. Do keep the names of DTOs, columns and endpoints in the description: they are evidence, not instructions.
- If an analyst has to settle a choice, write it **as a question**. Do not pick an option for them.

## Project settings

Before starting, identify these in the project's instructions, or ask:

- **Questions file:** where backend questions are kept (for example `docs/open-questions.md`), and whether it is committed.
- **Backend repository:** its local path and base branch (`<base>` below).
- **Test environment:** which non-production URL can go in a report.

## Phase 0. Frame it

1. **Check that the screen is reachable.** A mismatch visible only on a dead page is not a backend question. Check the route, the navigation entry (by exact match, not by prefix) and incoming links from live pages.
2. **Name the boundary:** one specific screen, tab or block, not "the whole page".
3. **Read the header of the questions file** for its format and rules.
4. **Search the file for this finding** by field label, endpoint name and screen title. The defect you were given may already be a row in it. If so, deepen that row instead of adding a near-duplicate. If parts of one row turn out to need different decisions, split it and delete the original.
5. **Look for earlier analysis of the same area** in project notes. It may contain a refutation ("not a defect, that branch is unreachable") or a mechanism that is already worked out.

## Phase 1. Frontend: what the screen shows and where it comes from

Go from top to bottom, without skipping:

1. **What is rendered:** column constants, tab configuration or section component. Write down the keys and the **visible labels**. Describe findings to the backend team using labels, not variable names.
2. **What the response type declares:** does the field exist at all?
3. **What is actually read:** the row mapper, form defaults, normalizer. A field can exist in the type and never be read by the mapper. Then the fault is ours.
4. **Where the data comes from after saving.** If a form rebuilds itself from the mutation response and the cached query is not invalidated, the symptom is "visible after saving, gone after a reload". That means the write endpoint returns the field and the read endpoint does not.
5. **Whether a user can save the field at all.** Before writing "fill it in and save", check `readOnly` flags, the conditions that enable saving and any tab permissions. The mechanism can be right while the scenario is impossible. If the field is not editable, report it as a read-only question.

## Phase 2. Backend: read only

The backend's working tree may hold someone else's unsaved work. **No `checkout`, `pull`, `stash` or edits.** Fetch once, then read from the remote ref:

```bash
git -C <backend-repo> fetch origin <base>
git -C <backend-repo> show origin/<base>:<path>
git -C <backend-repo> grep -n <pattern> origin/<base> -- <path>
git -C <backend-repo> ls-tree -r --name-only origin/<base>
```

Do not search the working tree with `rg` or `grep`: you may read uncommitted code as if it were shipped.

Walk the whole chain and answer "present / missing" for each link:

**migration column → entity field → intermediate row or projection → response DTO → mapper → query (fetch or join)**

Separately check **every** endpoint that returns this entity: list, detail, write responses, printable or document export. Fixing one while the others stay broken brings half the defect back.

Read the backend's own instructions first, such as `AGENTS.md`. They may contain prohibitions that change what you can ask for (see trap 3).

## Phase 3. Traps

**1. Check the whole block, not just the fields in the ticket.**
Suppose a ticket names two empty dates in a "Delivery" block. Count the keys in the block on the frontend, how many arrive, and how many exist on the backend. Others may be empty too, and some may not exist at all. Fixing only what the ticket names invites a second defect about the same block.

**2. Compare the on-screen label with the meaning of the column.**
Suppose a field labelled "Shipping date" is backed by a column whose comment says "date the order was packed". Returning it "as requested" shows wrong data under a correct-looking label, which is worse than an empty cell. A mismatch between label and column is a finding of its own, so name it.

**3. Before asking for a field, check whether it is deprecated.**
Look for markers such as `@Deprecated` and read the backend's rules on legacy fields. "Please return this column" may be a request to break their own rule. If it is deprecated, look for the live replacement before asking for anything.

**4. Look for a live replacement or a solved problem nearby.**
The same thing has often been done somewhere else, which turns "add a field" into "reuse the existing section". Search the same entity in a neighboring view, the same block on a neighboring record page, `git log -S` by field name, and any separate module covering the same domain. The neighboring solution is both a model for the backend team and the argument for doing it that way.

**5. Check reading and writing separately.**
Suppose the frontend sends `note` and the backend expects `note`, so writing works. But the backend returns `note` and the frontend reads `orderNote`, so reading fails. Looking at only one direction gives the wrong diagnosis. Check both and say which one is broken.

**6. A field name can differ between frontend and JSON without any error.**
The type checker will not catch it: the field is optional, it arrives as `undefined`, and the column stays empty. For every empty column, compare the name in the frontend type with the name in the DTO, character by character.

**7. Check what else breaks for the same reason.**
Fields missing from an API response may also be empty in an export built from the same data. One cause, two symptoms. Name the second in the same row.

**8. Verify a subagent's report on the claims that matter.**
If a subagent analyzed the backend, check for yourself whatever the decision depends on: whether the field is in the DTO, deprecation markers, allow-lists. Say plainly in your answer what you saw yourself and what comes from the agent.

## Phase 4. Sort and record

Every mismatch goes into one of two lists.

**Fix on our side** (not recorded in the questions file):

- the field name differs and the frontend fix is obvious and safe;
- the field arrives but the mapper does not read it;
- the label or format is ours.

These go through the project's normal task, branch and merge request flow.

**Questions file:** one row in the open table:

| What is wrong for the user | Where it is visible | What we ask of the backend | Found |
| --- | --- | --- | --- |

- **Column 1, from the user's point of view:** no field names or task codes. Someone will read this a month from now.
- **Column 2:** the path through the interface, the endpoint, and a link to a non-production environment. Never a production link.
- **Column 3:** what we ask and why: where the chain breaks, where this is already done correctly, which decisions are open. No step-by-step plan through their files.
- **Column 4:** the date found, from `date +%F`.

Delete resolved rows rather than keeping them as history. If something is agreed but not shipped, note at the end of the row which version it is expected in.

## Phase 5. Wrap up

- Reconcile the numbers: how many empty fields were reported, how many were found, how many you fixed, how many became questions. A mismatch is a reason to return to trap 1.
- Check for findings outside the original request. Do not slip them into someone else's task and do not lose them: add a separate row or raise them with the user explicitly.
- If you found a label and data mismatch (trap 2), name it separately, even if the defect was about something else.

## What not to do

- Do not fix the backend or create backend branches without an explicit request.
- Do not record in the questions file what the frontend can fix itself.
- Do not choose a data source for the analyst when several live candidates exist.
- Do not present a subagent's report as your own verification.
- Do not give production links or reproduce defects on production.

## Related skills

- `openapi-contract`: read an endpoint's contract from its spec or probe it live. Useful in phase 2 when the backend source is not available.
