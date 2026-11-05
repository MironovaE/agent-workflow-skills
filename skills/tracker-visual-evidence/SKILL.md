---
name: tracker-visual-evidence
description: Document a visual fix in an issue tracker with trustworthy before/after screenshots and clear markings of the defect. Use when the user asks for a UI or responsive-layout task with visual proof, says "add before/after screenshots", "attach visual evidence", "document this layout fix", or "приложи скриншоты до/после".
---

# Task with visual evidence

A screenshot in a task is a claim about what really happened on screen. This skill keeps that claim
honest and makes the difference obvious at a glance.

## 1. Start from the card

Follow `tracker-task` for tracker access, the card format and the explicit yes before writing.
Check defects only locally or in a non-production environment.

## 2. Collect the facts

Before creating or updating the card, gather:

- the current diff;
- the exact screen and its direct link in the check environment;
- the browser and viewport size;
- the difference you actually observed;
- how a person can check it by hand.

If part of the project's browser and viewport matrix has not been checked yet, say that in the card.

## 3. Capture a real before and after

For each fixed visual defect, attach two screenshots of the same screen at the same size.

- Capture the real browser state.
- If the "before" was reproduced from an earlier version or by temporarily reverting a style, label
  it that way in the task. Never present a reconstruction as the original capture.
- Do not alter page data or API responses to make the picture look better.
- Keep the unmarked source images if you captured them before adding markings.

## 4. Mark the difference

- Highlight the problem edge or element with a simple frame or arrow and a short label: "Before: …"
  or "After: …".
- Markings must not cover the defect or change the UI content.
- For a layout defect, add one comparison image: large crops of the same area side by side, with the
  cut-off line clear on the left and the result visible on the right.
- Open the finished image at normal scale. The difference should be clear without reading the task
  description. If it is not, crop closer or redo the markings.

## 5. Upload and verify

1. Upload both screenshots and the comparison to the card.
2. Open the card again.
3. Check the number, text, links and attachment count, and that each image opens.
4. Remove earlier failed attachments after replacing them.

A successful upload response alone does not mean the card is finished.

## 6. If the tracker session is unavailable

Prepare the text and files, name the specific obstacle, and ask the user to log in in the browser.
Do not ask for a password or token in chat, and do not file the task somewhere else instead.

## Scope

One screen gives one checkable result. When a larger review spans several screens, update its task
with actual results as each screen is done, and do not promise what has not been checked.
