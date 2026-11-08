import assert from "node:assert/strict"
import { test } from "node:test"
import { mkdtempSync, readFileSync, readdirSync, rmSync, statSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { setTimeout as sleep } from "node:timers/promises"
import { applyEvent, bridgePath, createState, createWriter, payload, reconcilePending, sessionRecord } from "./bridge.js"
import { startBridge } from "./runtime.js"

const session = (id = "ses_root", extra = {}) => ({ id, title: "Review", location: { directory: "/work" },
  time: { updated: 1_730_000_000_000 }, ...extra })
const event = (type, id, data = {}) => ({ type, id: `evt_${id}`, created: 1_730_000_001_000,
  data: { sessionID: "ses_root", ...data } })
function state() {
  const result = createState()
  const record = sessionRecord(session())
  result.sessions.set(record.id, record)
  return result
}

test("contract: root sessions, epoch seconds, no startup completions or private content", () => {
  assert.equal(sessionRecord(session("ses_child", { parentID: "ses_root" })), undefined)
  assert.equal(sessionRecord(session("ses_invalid", { location: { directory: "relative" } })), undefined)
  const model = state()
  reconcilePending(model, "ses_root", "question", [{ id: "frm_pending", sessionID: "ses_root",
    title: "secret prompt", fields: [{ default: "secret answer" }] }], 1730000000)
  const result = payload(model, 1_730_000_001_000)
  assert.deepEqual(Object.keys(result), ["version", "updatedAt", "sessions", "notices", "pending"])
  assert.equal(result.updatedAt, 1730000001)
  assert.equal(result.sessions[0].updatedAt, 1730000000)
  assert.equal(result.notices.length, 0)
  assert.equal(result.pending[0].requestID, "frm_pending")
  assert.ok(!JSON.stringify(result).includes("secret"))
})

test("only execution lifecycle yields working/done/error/interrupted; event IDs deduplicate", () => {
  const model = state()
  for (const type of ["session.step.ended", "session.step.failed", "session.status", "session.idle"]) {
    assert.equal(applyEvent(model, event(type, type)), false)
  }
  for (const [suffix, kind] of [["started", "working"], ["succeeded", "done"], ["failed", "error"], ["interrupted", "interrupted"]]) {
    const input = event(`session.execution.${suffix}`, suffix, { error: { message: "secret" } })
    assert.equal(applyEvent(model, input), true)
    assert.equal(applyEvent(model, input), false)
    assert.equal(model.notices.at(-1).kind, kind)
    assert.equal(model.notices.at(-1).id, input.id)
  }
  assert.ok(!JSON.stringify(payload(model)).includes("secret"))
  assert.equal(applyEvent(model, event("session.execution.succeeded", "child", { sessionID: "ses_child" })), false)
  for (let i = 0; i < 150; i++) applyEvent(model, event("session.execution.started", `run${i}`))
  assert.equal(model.notices.length, 128)
  assert.equal(model.notices.at(-1).id, "evt_run149")
})

test("form and permission native request IDs resolve separately; snapshots clear missed replies", () => {
  const model = state()
  applyEvent(model, event("form.created", "question", { form: { id: "frm_1", sessionID: "ses_root" } }))
  applyEvent(model, event("permission.asked", "permission", { id: "per_1", resources: ["secret"] }))
  assert.equal(model.pending.size, 2)
  applyEvent(model, event("permission.replied", "reply", { requestID: "per_1", reply: "once" }))
  assert.equal(model.pending.size, 1)
  assert.equal(model.notices.at(-1).requestID, "per_1")
  applyEvent(model, event("form.cancelled", "cancel", { id: "frm_1" }))
  assert.equal(model.pending.size, 0)
  applyEvent(model, event("form.created", "question2", { form: { id: "frm_2", sessionID: "ses_root" } }))
  reconcilePending(model, "ses_root", "question", [], 1730000002)
  assert.equal(model.pending.size, 0)
  assert.equal(model.notices.at(-1).kind, "question")
  assert.ok(!JSON.stringify(payload(model)).includes("secret"))
})

test("atomic private writer, location hash, fail-open, and old cleanup preserves newer writer", () => {
  const home = mkdtempSync(join(tmpdir(), "dyland-bridge-"))
  try {
    const first = createWriter("/work", home)
    const second = createWriter("/work", home)
    assert.match(first.file, /[0-9a-f]{16}\.json$/)
    assert.equal(first.file, bridgePath("/work", home))
    assert.notEqual(first.file, bridgePath("/other", home))
    assert.equal(first.publish(payload(state())), true)
    assert.equal(statSync(first.file).mode & 0o777, 0o600)
    assert.equal(statSync(join(first.file, "..")).mode & 0o777, 0o700)
    assert.deepEqual(readdirSync(join(first.file, "..")), [first.file.split("/").at(-1)])
    second.publish({ fresh: true })
    first.close()
    assert.deepEqual(JSON.parse(readFileSync(first.file, "utf8")), { fresh: true })
    assert.equal(first.publish({ stale: true }), false)
    assert.equal(createWriter("/work", "/dev/null").publish({}), false)
    second.close()
  } finally { rmSync(home, { recursive: true, force: true }) }
})

test("runtime: global root cursor pages, live file publication, resync, and abort cleanup", async () => {
  const home = mkdtempSync(join(tmpdir(), "dyland-runtime-"))
  const events = []
  let wake
  let aborted = false
  const calls = []
  const snapshotCalls = []
  const getCalls = []
  const foreign = (id) => session(id, { location: { directory: "/other" } })
  let permissions = [{ id: "per_boot", sessionID: "ses_root" }]
  let forms = [{ id: "frm_boot", sessionID: "ses_root" }]
  const ctx = {
    location: { directory: "/work" },
    session: {
      async list(input) {
        calls.push(input)
        return input.cursor ? { data: [foreign("ses_second")], cursor: {} } :
          { data: [session()], cursor: { next: "page2" } }
      },
      async get({ sessionID }) { getCalls.push(sessionID); return foreign(sessionID) },
      form: { async list({ sessionID }) {
        snapshotCalls.push(sessionID)
        return forms.filter((item) => item.sessionID === sessionID)
      } },
    },
    permission: { async list({ sessionID }) {
      snapshotCalls.push(sessionID)
      return permissions.filter((item) => item.sessionID === sessionID)
    } },
    event: {
      async *subscribe({ signal }) {
        signal.addEventListener("abort", () => { aborted = true; wake?.() }, { once: true })
        while (!signal.aborted) {
          if (!events.length) await new Promise((resolve) => { wake = resolve })
          while (events.length && !signal.aborted) yield events.shift()
        }
      },
    },
  }
  const close = startBridge(ctx, { home, heartbeat: 30, resync: 100 })
  const read = () => JSON.parse(readFileSync(bridgePath("/work", home), "utf8"))
  const until = async (check) => {
    for (let i = 0; i < 100; i++) { if (check()) return; await sleep(10) }
    assert.fail("bridge condition timed out")
  }
  try {
    await until(() => read().pending.length === 2)
    assert.equal(read().notices.length, 0)
    assert.deepEqual(calls[0], { parentID: null, limit: 200, order: "desc" })
    assert.deepEqual(calls[1], { cursor: "page2", limit: 199 })
    assert.equal(read().sessions.length, 2)
    assert.ok(snapshotCalls.every((id) => id === "ses_root"))
    events.push(
      { ...event("session.execution.succeeded", "foreign-known", { sessionID: "ses_second" }), location: { directory: "/other" } },
      { ...event("session.execution.succeeded", "foreign-unknown", { sessionID: "ses_unknown" }), location: { directory: "/other" } },
      event("session.execution.succeeded", "foreign-known-unlocated", { sessionID: "ses_second" }),
      event("session.execution.succeeded", "foreign-unlocated", { sessionID: "ses_unlocated" }),
      event("session.execution.succeeded", "live"),
    )
    wake?.()
    await until(() => read().notices.some((notice) => notice.id === "evt_live"))
    permissions = []
    forms = []
    await until(() => read().pending.length === 0)
    assert.equal(read().notices.length, 1)
    assert.deepEqual(getCalls, ["ses_unlocated"])
    assert.ok(snapshotCalls.every((id) => id === "ses_root"))
    close()
    const final = readFileSync(bridgePath("/work", home), "utf8")
    await sleep(150)
    assert.equal(readFileSync(bridgePath("/work", home), "utf8"), final)
    assert.equal(aborted, true)
  } finally { close(); rmSync(home, { recursive: true, force: true }) }
})
