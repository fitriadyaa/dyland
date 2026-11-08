import { createHash, randomUUID } from "node:crypto"
import { chmodSync, lstatSync, mkdirSync, renameSync, unlinkSync, writeFileSync } from "node:fs"
import { homedir } from "node:os"
import { isAbsolute, join } from "node:path"

export const eventTypes = [
  "session.execution.started", "session.execution.succeeded", "session.execution.failed",
  "session.execution.interrupted", "form.created", "form.replied", "form.cancelled",
  "permission.asked", "permission.replied", "session.created", "session.renamed",
  "session.moved", "session.deleted", "session.archived", "session.unarchived",
]
const lifecycle = {
  "session.execution.started": "working",
  "session.execution.succeeded": "done",
  "session.execution.failed": "error",
  "session.execution.interrupted": "interrupted",
}
const text = (value) => typeof value === "string" && value.length > 0
export const seconds = (milliseconds) => Math.max(0, milliseconds / 1000)
const key = (kind, sessionID, requestID) => JSON.stringify([kind, sessionID, requestID])

export function createState() {
  return { sessions: new Map(), notices: [], pending: new Map() }
}

export function sessionRecord(info) {
  if (!text(info?.id) || info.parentID != null || !isAbsolute(info.location?.directory ?? "") ||
      !Number.isFinite(info.time?.updated)) return undefined
  return { id: info.id, title: typeof info.title === "string" ? info.title : "",
    directory: info.location.directory, updatedAt: seconds(info.time.updated) }
}

export function applyEvent(state, event) {
  if (!text(event?.id) || !Number.isFinite(event.created) || !event.data) return false
  const data = event.data
  const sessionID = event.type === "form.created" ? data.form?.sessionID : data.sessionID
  if (!state.sessions.has(sessionID)) return false
  if (state.notices.some((notice) => notice.id === event.id)) return false
  let kind = lifecycle[event.type]
  let requestID
  if (event.type === "form.created") {
    kind = "question"
    requestID = data.form?.id
  } else if (event.type === "permission.asked") {
    kind = "permission"
    requestID = data.id
  } else if (["form.replied", "form.cancelled", "permission.replied"].includes(event.type)) {
    kind = "resolved"
    requestID = event.type === "permission.replied" ? data.requestID : data.id
    if (!text(requestID)) return false
    const pendingKind = event.type.startsWith("form.") ? "question" : "permission"
    state.pending.delete(key(pendingKind, sessionID, requestID))
  }
  if (!kind || ((kind === "question" || kind === "permission") && !text(requestID))) return false
  const notice = { id: event.id, sessionID, kind, timestamp: seconds(event.created),
    ...(requestID ? { requestID } : {}) }
  if (kind === "question" || kind === "permission") {
    state.pending.set(key(kind, sessionID, requestID), notice)
  }
  state.notices.push(notice)
  state.notices = state.notices.slice(-128)
  const session = state.sessions.get(sessionID)
  session.updatedAt = Math.max(session.updatedAt, notice.timestamp)
  return true
}

// Snapshot reconciliation never manufactures notices, especially startup completions.
export function reconcilePending(state, sessionID, kind, requests, timestamp) {
  if (!Array.isArray(requests) || !state.sessions.has(sessionID)) return
  const current = new Set()
  for (const request of requests) {
    if (!text(request?.id) || request.sessionID !== sessionID) continue
    const id = key(kind, sessionID, request.id)
    current.add(id)
    if (!state.pending.has(id)) state.pending.set(id, {
      id: request.id, sessionID, kind, timestamp, requestID: request.id,
    })
  }
  for (const [id, pending] of state.pending) {
    if (pending.sessionID === sessionID && pending.kind === kind && !current.has(id)) state.pending.delete(id)
  }
}

export function payload(state, now = Date.now()) {
  const sessions = [...state.sessions.values()].slice(0, 200)
  const ids = new Set(sessions.map((session) => session.id))
  return { version: 1, updatedAt: seconds(now), sessions,
    notices: state.notices.filter((notice) => ids.has(notice.sessionID)).slice(-128),
    pending: [...state.pending.values()].filter((pending) => ids.has(pending.sessionID)) }
}

export function bridgePath(directory, home = homedir()) {
  if (!isAbsolute(directory)) throw new TypeError("Location directory must be absolute")
  const hash = createHash("sha256").update(directory).digest("hex").slice(0, 16)
  return join(home, "Library", "Application Support", "Dyland", "bridge", `${hash}.json`)
}

export function createWriter(directory, home) {
  const file = bridgePath(directory, home)
  const folder = join(file, "..")
  const owner = randomUUID()
  let closed = false
  return {
    file,
    publish(value) {
      if (closed) return false
      const temporary = join(folder, `.${owner}.${randomUUID()}.tmp`)
      try {
        mkdirSync(folder, { recursive: true, mode: 0o700 })
        if (!lstatSync(folder).isDirectory() || lstatSync(folder).isSymbolicLink()) return false
        chmodSync(folder, 0o700)
        writeFileSync(temporary, JSON.stringify(value), { mode: 0o600, flag: "wx" })
        renameSync(temporary, file)
        return true
      } catch {
        return false
      } finally {
        try { unlinkSync(temporary) } catch { /* Already renamed or unavailable. */ }
      }
    },
    close() {
      closed = true
      // ponytail: no native conditional-unlink primitive; leave final heartbeat for reader TTL.
      // Never risk unlinking a newer same-location writer during reload or another process.
    },
  }
}
