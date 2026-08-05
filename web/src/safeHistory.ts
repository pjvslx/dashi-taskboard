function isHistoryUrlRestriction(error: unknown): boolean {
  return error instanceof DOMException && error.name === "SecurityError"
    || error instanceof Error && error.message.includes("history state object with URL");
}

function warnHistoryUrlSkipped(error: unknown) {
  console.warn("Taskboard could not update the browser URL in this embedded host.", error);
}

export function safeReplaceHistoryState(state: unknown, title: string, url: string | URL) {
  try {
    window.history.replaceState(state, title, url);
  } catch (error) {
    if (!isHistoryUrlRestriction(error)) throw error;
    warnHistoryUrlSkipped(error);
  }
}

export function safePushHistoryState(state: unknown, title: string, url: string | URL) {
  try {
    window.history.pushState(state, title, url);
  } catch (error) {
    if (!isHistoryUrlRestriction(error)) throw error;
    warnHistoryUrlSkipped(error);
  }
}
