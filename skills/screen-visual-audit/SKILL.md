---
name: screen-visual-audit
description: Review the rendering of one live application screen at a time across the project's browser and viewport matrix, and state honestly what was and was not checked. Use when the user asks to check how a screen looks, test responsive layout, or go through screens one by one, or says "проверь отображение", "проверь адаптив", "пройди экраны". Not a replacement for a functional smoke test.
---

# Visual review of live screens

The question here is whether a real person can see and use the screen at each supported size. Check
one screen at a time so that every result is specific and can be verified.

## Project settings

Define the matrix for your project, in the repository's agent instructions or a local copy of this
skill:

| Setting | Example |
| --- | --- |
| Environment to check | Local build against a test API, or a test environment |
| Environment for reading only | `<production URL>` |
| Required browsers | Chrome and Safari on desktop |
| Required viewports | Desktop, tablet portrait, tablet landscape |
| Real-device checks | Tablet on a device or simulator, when available |
| Out of scope | For example, phones and other browsers |
| Type check and lint commands | `<project commands>` |

If the matrix is not defined, ask for it instead of inventing one.

## Procedure

1. **Pick a live screen.** Read the repository's instructions and check `git status --short`. Take
   one screen from the current navigation and its route. Skip removed, hidden and legacy pages, even
   if their files are still in the repository.

2. **Use a safe environment.** Work locally or in a test environment. Production may be read for
   task context but is never used to reproduce a defect or check a fix. If you start a local server,
   first check the port and API target the project requires.

3. **Check the real render.** Open the screen and try its main actions in each required browser and
   viewport. Name each method accurately: resizing a window or using browser emulation is
   **emulation**, not a physical device.

4. **Inspect each size.** Check visible blocks, cut-off text and actions, horizontal overflow,
   dialogs, scrolling and access to key buttons.

   `scrollWidth <= innerWidth` is not enough, because a container with `overflow: hidden` can cut
   off elements while the page reports no overflow. Compare child element rectangles with their
   container's bounds, and look at a screenshot whenever you can capture one.

5. **Fix within scope.** If the task allows fixes, change only the affected screen. Repeat the same
   sizes and browsers afterwards, then run the project's type check and lint on the changed files.
   Do not leave temporary tests or screenshots in the tracked tree.

6. **Report one screen.** State what was checked, the sizes and browsers, the defects found and fixed,
   and the limits of the check. Do not call a browser visually checked if you only collected DOM
   metrics from it.

## Report template

```text
Screen: <name and route>
Checked: <browser> at <size>, method: real device | simulator | emulation | DOM metrics only
Defects found: <list, or none>
Fixed: <list, or none>
Not checked: <what remains, and why>
```

## Related skills

- A smoke test finds screens that crash. It does not show that a responsive layout is good, and this
  skill does not replace it.
- `tracker-visual-evidence` documents a fixed defect with before/after screenshots.
