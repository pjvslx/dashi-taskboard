# Windows Resident Injector Design

## Problem

The Taskboard injector and its local service disappear at roughly the same time
a Codex task finishes. Injector diagnostics contain regular heartbeats followed
by an abrupt stop, with no JavaScript exception, signal, or exit event. This is
consistent with Windows terminating the Codex task's descendant process tree.
Node's detached process option is insufficient when the process remains in the
same Windows job object.

## Chosen Approach

Keep `start-codex-taskboard.bat` as the user-facing launcher, but delegate the
resident injector to Windows Task Scheduler. Task Scheduler starts the process
from its service, outside the lifecycle of the Codex task that invoked the
launcher.

A dedicated PowerShell script will install or update one scheduled task for the
selected debugging port and start it immediately. The task runs Node directly
with `scripts/codex-injector.mjs --watch --open --attach-existing`, uses the
repository as its working directory, and has no execution time limit.

## Lifecycle

1. The batch launcher starts Codex with remote debugging and waits for its main
   renderer target.
2. The launcher stops any old Taskboard listener that belongs to the previous
   runtime.
3. The launcher registers or updates the Task Scheduler entry and starts it.
4. The scheduled process starts the Taskboard service, injects the panel, and
   keeps the CDP connection alive.
5. A later launcher run replaces the task definition and starts a fresh
   instance, so repository paths and ports cannot become stale.

## Diagnostics And Failure Handling

The installer writes registration and launch failures to
`.data/logs/start-codex-taskboard.log`. The injector continues writing startup,
heartbeat, child-service exit, signal, and fatal diagnostics to
`.data/logs/codex-injector.log`. The launcher fails visibly when registration or
startup fails instead of claiming that the panel is running.

