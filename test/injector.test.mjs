import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";

const source = await readFile(new URL("../scripts/codex-injector.mjs", import.meta.url), "utf8");
const launcherSource = await readFile(
  new URL("../start-codex-taskboard.bat", import.meta.url),
  "utf8",
);
const runtimeSource = await readFile(
  new URL("../scripts/codex-injector-runtime.mjs", import.meta.url),
  "utf8",
);
const scheduledTaskInstallerSource = await readFile(
  new URL("../scripts/install-codex-resident-task.ps1", import.meta.url),
  "utf8",
).catch(() => "");
const scheduledTaskRunnerSource = await readFile(
  new URL("../scripts/codex-resident-task-runner.mjs", import.meta.url),
  "utf8",
).catch(() => "");
const scheduledTaskLauncherSource = await readFile(
  new URL("../scripts/codex-resident-task-launcher.vbs", import.meta.url),
  "utf8",
).catch(() => "");
const packageJson = JSON.parse(
  await readFile(new URL("../package.json", import.meta.url), "utf8"),
);

test("the resident injector supervises the fixed local Taskboard service", () => {
  assert.match(source, /function createTaskboardSupervisor/);
  assert.match(source, /await isReachable\(taskboardHealthUrl\)/);
  assert.match(source, /ensureInFlight/);
  assert.match(source, /await supervisor\.ensure\(\)/);
  assert.match(source, /it will be restarted automatically/);
  assert.match(source, /AbortSignal\.timeout\(1_500\)/);
});

test("the CDP bridge accepts only service ensure and native Skill composer prefill actions", () => {
  assert.match(source, /const hostBindingName = "__codexTaskboardHostV1"/);
  assert.match(runtimeSource, /request\.action === "ensure"/);
  assert.match(runtimeSource, /request\.action === "prefill-task-composer"/);
  assert.match(runtimeSource, /request\.instruction\.length <= 1_024/);
  assert.match(runtimeSource, /request\.skillPath\.length <= 1_024/);
  assert.match(source, /function prefillTaskComposerViaCdp/);
  assert.match(source, /cdp\.send\("Input\.insertText", \{ text: "\$" \}\)/);
  assert.match(source, /data-composer-overlay-floating-ui/);
  assert.match(source, /button\[data-list-navigation-item="true"\]/);
  assert.match(source, /\[skill-mention-name\]/);
  assert.match(source, /skill-mention-path/);
  assert.match(source, /function focusComposerAfterSkillMention/);
  assert.match(source, /range\.selectNodeContents\(editor\)/);
  assert.match(source, /range\.collapse\(false\)/);
  assert.match(source, /await focusComposerAfterSkillMention\(cdp, executionContextId\)/);
  assert.match(source, /cdp\.send\("Input\.insertText", \{ text: ` \$\{instruction\}` \}\)/);
  assert.match(source, /Runtime\.bindingCalled/);
  assert.match(runtimeSource, /params\.executionContextId/);
  assert.match(source, /hostResponse/);
  assert.match(source, /if \(keepAlive\) await installTaskboardHostBinding/);
  assert.match(source, /publishHostHeartbeat/);
  assert.match(source, /__codexTaskboardHostHeartbeatV1/);
});

test("the CDP bridge exposes only the fixed Taskboard automation operations", () => {
  assert.match(source, /parseTaskboardAutomationHostRequest/);
  assert.match(source, /reconcileTaskboardAutomation/);
  assert.match(runtimeSource, /request\.action === "automation"/);
  assert.match(source, /function requestCodexAutomationViaCdp/);
  assert.match(source, /new Set\(\[\s*"list-automations",\s*"automation-create",\s*"automation-update",\s*\]\)/);
  assert.match(source, /bridge\.sendMessageFromView\(\{\s*type: "fetch",\s*requestId,/);
  assert.match(source, /method: "POST"/);
  assert.match(source, /vscode:\/\/codex\/\$\{method\}/);
  assert.match(source, /body: JSON\.stringify\(params\)/);
  assert.match(source, /message\.type !== "fetch-response"/);
  assert.match(source, /message\.responseType/);
  assert.match(source, /message\.status/);
  assert.match(source, /message\.bodyJsonString/);
  assert.doesNotMatch(source, /automation-delete/);
  assert.doesNotMatch(source, /automations\.toml/);
});

test("the package injection command remains resident for tab-triggered recovery", () => {
  assert.match(packageJson.scripts["codex:inject"], /--watch/);
  assert.match(packageJson.scripts["codex:daemon"], /--daemon --open/);
  assert.match(source, /function startResidentInjector/);
  assert.match(source, /const defaultCodexDebuggingPort = 9229/);
  assert.match(source, /port: defaultCodexDebuggingPort/);
  assert.match(source, /--startup-token/);
  assert.match(source, /__codexTaskboardHostStartupTokenV1/);
});

test("the daemon command remains available while the Windows launcher uses independent hosting", () => {
  assert.doesNotMatch(launcherSource, /npm run codex:daemon/);
  assert.doesNotMatch(launcherSource, /npm run codex:inject -- --port %PORT% --open --attach-existing/);
  assert.match(launcherSource, /install-codex-resident-task\.ps1/);
  assert.match(source, /async function startResidentInjectorForDaemon/);
  assert.match(source, /startResidentInjector\(port, options\.open, options\.attachExisting, startupToken\)/);
  assert.match(source, /await waitForResidentInjectorReady\(port, launcher\.pid, startupToken, sourceHash\)/);
  assert.match(source, /startResidentInjectorForDaemon\(port, options\)/);
});

test("the Windows launcher hosts the resident injector outside the Codex task tree", () => {
  assert.match(launcherSource, /install-codex-resident-task\.ps1/);
  assert.doesNotMatch(launcherSource, /npm run codex:daemon/);
  assert.match(scheduledTaskInstallerSource, /Register-ScheduledTask/);
  assert.match(scheduledTaskInstallerSource, /Start-ScheduledTask/);
  assert.match(scheduledTaskInstallerSource, /ExecutionTimeLimit\s+\(\[TimeSpan\]::Zero\)/);
  assert.match(scheduledTaskInstallerSource, /RestartCount\s+3/);
  assert.match(scheduledTaskRunnerSource, /codex-injector\.mjs/);
  assert.match(scheduledTaskRunnerSource, /"--watch"/);
  assert.doesNotMatch(scheduledTaskRunnerSource, /"--open"/);
  assert.match(scheduledTaskRunnerSource, /appendFileSync/);
  assert.match(scheduledTaskRunnerSource, /resident-start/);
  assert.match(scheduledTaskRunnerSource, /resident-exit/);
  assert.match(scheduledTaskRunnerSource, /function startInjector\(\)/);
  assert.match(scheduledTaskRunnerSource, /resident-child-restart/);
  assert.match(scheduledTaskRunnerSource, /restartTimer = setTimeout\(startInjector, 1_000\)/);
  assert.match(launcherSource, /-ProjectRoot "%REPO_DIR%\." -LogPath "%LOG_FILE%"/);
  assert.match(scheduledTaskInstallerSource, /Test-Path -LiteralPath \$LogPath -PathType Container/);
  assert.match(scheduledTaskInstallerSource, /Join-Path \$LogPath 'start-codex-taskboard\.log'/);
  assert.match(scheduledTaskInstallerSource, /wscript\.exe/i);
  assert.match(scheduledTaskInstallerSource, /codex-resident-task-launcher\.vbs/);
  assert.match(scheduledTaskLauncherSource, /WScript\.Shell/);
  assert.match(scheduledTaskLauncherSource, /\.Run\(command, 0, True\)/i);
});

test("attach reconciles the renderer against a hashed current injection source", () => {
  assert.match(source, /createHash\("sha256"\)/);
  assert.match(source, /__CODEX_TASKBOARD_SOURCE_HASH__/);
  assert.match(source, /sourceHash: window\.__codexTaskboardInjection__\?\.sourceHash \|\| null/);
  assert.match(source, /const injectionScriptIdentifierName = "__CODEX_TASKBOARD_SCRIPT_IDENTIFIER__"/);
  assert.match(source, /scriptIdentifier: window\[\$\{JSON\.stringify\(injectionScriptIdentifierName\)\}\] \|\| null/);
  assert.match(source, /Page\.removeScriptToEvaluateOnNewDocument/);
  assert.match(source, /Page\.addScriptToEvaluateOnNewDocument/);
  assert.match(source, /reconcileInjectionRuntime/);
  assert.match(source, /expectedSourceHash/);
});

test("watch mode waits through startup renderer gaps and logs injector output", () => {
  assert.match(source, /async function waitForInitialInjection/);
  assert.match(source, /Waiting for Codex renderer: \$\{error\.message\}/);
  assert.match(source, /await waitForInitialInjection\(/);
  assert.doesNotMatch(source, /const firstResults = await injectAll\(/);
  assert.match(scheduledTaskRunnerSource, /child\.stdout\.on\("data"/);
  assert.match(scheduledTaskRunnerSource, /child\.stderr\.on\("data"/);
  assert.match(scheduledTaskRunnerSource, /appendFileSync\(logPath, chunk\)/);
});

test("injector records exit diagnostics before returning code 1", () => {
  assert.match(source, /const injectorLogPath = path\.join\(projectRoot, "\.data", "logs", "codex-injector\.log"\)/);
  assert.match(source, /function writeInjectorDiagnostic/);
  assert.match(source, /function startInjectorHeartbeat/);
  assert.match(source, /writeInjectorDiagnostic\("heartbeat"/);
  assert.match(source, /writeInjectorDiagnostic\("signal"/);
  assert.match(source, /writeInjectorDiagnostic\("taskboard-child-exit"/);
  assert.match(source, /writeInjectorDiagnostic\("taskboard-child-error"/);
  assert.match(source, /process\.on\("uncaughtExceptionMonitor"/);
  assert.match(source, /process\.on\("unhandledRejection"/);
  assert.match(source, /process\.on\("exit"/);
  assert.match(source, /writeInjectorDiagnostic\("fatal", error\)/);
  assert.match(source, /console\.error\(error\.stack \|\| error\.message\)/);
});

test("attach-existing honors an explicit open request even when the old page was closed", () => {
  assert.match(source, /const shouldShowTaskboard = shouldOpen \|\| reconciled\.shouldRemainOpen/);
  assert.match(source, /if \(shouldOpen && !reconciled\.shouldRemainOpen\)/);
  assert.match(source, /expression: "window\.__codexTaskboardInjection__\?\.open\(\)"/);
  assert.match(source, /waitForInjectionStatus\(\s*cdp,\s*shouldShowTaskboard,/);
});

test("the injector ignores auxiliary Codex windows", () => {
  assert.match(source, /!target\.url\?\.includes\("initialRoute=%2Fglobal-dictation"\)/);
  assert.match(source, /!target\.url\?\.includes\("initialRoute=%2Favatar-overlay"\)/);
});

test("a completed web build refreshes an already-open Codex iframe", () => {
  assert.match(packageJson.scripts.build, /--refresh-if-running/);
  assert.match(packageJson.scripts["codex:refresh"], /--refresh/);
  assert.match(source, /async function refreshTaskboardFrames/);
  assert.match(source, /function codexDebuggingPorts/);
  assert.match(source, /--remote-debugging-port=/);
  assert.match(source, /taskboard\.reloadFrame\(\)/);
  assert.match(source, /__codex_taskboard_refresh/);
  assert.match(source, /await restartResidentInjectorForRefresh\(port\)/);
});

test("the injected iframe follows the configured local service port", () => {
  assert.match(source, /const taskboardPageUrl = `\$\{taskboardOrigin\}\/\?host=codex`/);
  assert.match(source, /window\.__CODEX_TASKBOARD_URL__ = \$\{JSON\.stringify\(taskboardPageUrl\)\}/);
});
