import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";

const detailSource = await readFile(
  new URL("../web/src/components/TaskDetail.tsx", import.meta.url),
  "utf8",
);
const styles = await readFile(
  new URL("../web/src/styles.css", import.meta.url),
  "utf8",
);

test("commenting on a completed issue offers a manual reopen action", () => {
  assert.match(detailSource, /const \[reopenPromptVisible, setReopenPromptVisible\] = useState\(false\)/);
  assert.match(detailSource, /if \(currentTask\.status === "done"\) setReopenPromptVisible\(true\)/);
  assert.match(detailSource, /async function reopenCompletedTaskAfterComment\(\)/);
  assert.match(detailSource, /await saveTask\(\{ status: "todo" \}, "status"\)/);
  assert.match(detailSource, /setReopenPromptVisible\(false\)/);
  assert.match(detailSource, /className="comment-reopen-prompt"/);
  assert.match(detailSource, /重新打开/);
  assert.match(detailSource, /保持完成/);
  assert.match(styles, /\.comment-reopen-prompt/);
});
