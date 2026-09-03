---
name: dashi-todolist
description: "Turn a rough requirement from any local project into a reviewable TodoList, then create or update exactly one Dashi Taskboard issue per confirmed item. Use when the user invokes $dashi-todolist or asks to analyze project work before recording it as Taskboard issues."
---

# Dashi TodoList

Analyze first and write only after the user approves the exact list. Use `taskctl` for every Taskboard read or write. Mirror the user's language. Resolve `scripts/invoke-taskctl.ps1` relative to this `SKILL.md` and invoke it with PowerShell from any project directory.

## Resolve the target project

1. Determine the current Git root, or use the current working directory when outside Git.
2. Run the helper with `context current --cwd <path> --json`.
3. Prefer an exact workspace mapping. Otherwise use a unique same-name non-local project.
4. Report the selected Taskboard project before proposing work.
5. If there is no unique project, stop and ask the user to choose. Do not create a project or mapping automatically.

## Build the proposal

Inspect the relevant repository context without implementing the requirement. Split the rough request into independently reviewable user outcomes. Each TodoList item must include:

- issue title;
- objective and scope;
- acceptance criteria;
- suggested priority;
- dependency or relation to other proposed items, when needed;
- action: create a new issue or update a clearly matching existing issue.

List current project issues first and reuse or update an existing issue when it already represents the same outcome. Present the complete proposal and ask for explicit confirmation. Do not mutate Taskboard during the proposal turn.

## Apply the confirmed proposal

After confirmation:

1. Resolve the target project and list its issues again. If the project or relevant issue state changed, show the difference and reconfirm.
2. Create exactly one issue per confirmed new item with `issue create`, status `todo`, and a UTF-8 Markdown description file.
3. Update confirmed existing issues using their latest version and a merged description.
4. Pass `CODEX_THREAD_ID` when it is available so the issue records the originating task.
5. Add only the confirmed issue relations, using the latest issue versions.
6. Do not implement the issues or move them beyond `todo`.
7. If a command fails, inspect the returned state before retrying; never retry a mutation blindly.

Finish with a compact table containing each TodoList item, its issue identifier, action, and status.
