import test from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { stripTypeScriptTypes } from "node:module"

// OpenCode supplies Solid/TUI host at runtime. Validation does not need that host.
test("TUI routing validates request IDs without loading host UI", async () => {
  const source = readFileSync(new URL("./tui.ts", import.meta.url), "utf8")
    .replace('import { Plugin } from "@opencode/plugin/tui"', "const Plugin = { define: value => value }")
  const module = await import("data:text/javascript;base64," + Buffer.from(stripTypeScriptTypes(source)).toString("base64"))
  module.selfCheck()
  assert.equal(module.validRequest({ sessionID: "ses_valid", nonce: "../escape" }), false)
})
