import { Plugin } from "@opencode/plugin/tui"
import { randomUUID } from "node:crypto"
import { closeSync, constants, fstatSync, lstatSync, mkdirSync, openSync, readFileSync, renameSync, unlinkSync, writeFileSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

const sessionPattern = /^ses_[A-Za-z0-9_-]{1,240}$(?![\s\S])/
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$(?![\s\S])/i

type Request = { sessionID: string; nonce: string }
export function validRequest(value: unknown): value is Request {
  if (!value || typeof value !== "object") return false
  const request = value as Record<string, unknown>
  return typeof request.sessionID === "string" && sessionPattern.test(request.sessionID)
    && typeof request.nonce === "string" && uuidPattern.test(request.nonce)
}

function read(path: string): unknown {
  let descriptor: number | undefined
  try {
    descriptor = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW)
    const stat = fstatSync(descriptor)
    if (!stat.isFile() || stat.size > 128_000) return
    return JSON.parse(readFileSync(descriptor, "utf8"))
  } catch {
    return undefined
  } finally {
    if (descriptor !== undefined) closeSync(descriptor)
  }
}

function atomic(path: string, value: unknown) {
  const temporary = `${path}.${randomUUID()}.tmp`
  try {
    writeFileSync(temporary, JSON.stringify(value), { mode: 0o600, flag: "wx" })
    renameSync(temporary, path)
  } finally {
    try { unlinkSync(temporary) } catch {}
  }
}

export default Plugin.define({
  id: "dyland.tui",
  setup(context) {
    const directory = join(homedir(), "Library", "Application Support", "Dyland", "routes")
    try {
      mkdirSync(directory, { recursive: true, mode: 0o700 })
      const stat = lstatSync(directory)
      if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error("Unsafe route directory")
    } catch {
      context.ui.toast.show({ message: "Dyland: could not open the routes folder.", variant: "error" })
      return
    }

    // Unique per setup, not inherited environment. Token only pairs this launch with returned Ghostty UUID.
    const id = randomUUID()
    const token = process.env.DYLAND_ROUTE_TOKEN
    const launchToken = token && uuidPattern.test(token) ? token : undefined
    const path = join(directory, `${id}.json`)
    const requestPath = join(directory, `${id}.request.json`)
    const ackPath = join(directory, `${id}.ack.json`)
    const terminalPath = join(directory, `${id}.terminal.json`)
    let pending: Request | undefined
    let lastNonce: string | undefined
    let pendingAt = 0
    let publishedAt = 0
    let lastState = ""
    let warned = false

    function tick() {
      try {
        const current = context.ui.router.current()
        const currentSessionID = current.type === "session" ? current.sessionID : undefined
        const sessionIDs = [...new Set([
          ...(context.ui.tabs.enabled() ? context.ui.tabs.list().map((tab) => tab.sessionID) : []),
          ...(currentSessionID ? [currentSessionID] : []),
        ])].filter((sessionID) => sessionPattern.test(sessionID)).slice(0, 1_000)
        const now = Date.now()
        const state = JSON.stringify({ sessionIDs, currentSessionID })
        if (state !== lastState || now - publishedAt >= 2_000) {
          atomic(path, {
            id, sessionIDs, currentSessionID, launchToken,
            updatedAt: now / 1_000,
            directory: (context.location ?? context.data.location.default()).directory,
          })
          lastState = state
          publishedAt = now
        }

        if (pending) {
          // ACK only after router reports requested session, not merely after dispatch.
          if (currentSessionID === pending.sessionID) {
            atomic(ackPath, pending)
            pending = undefined
          } else if (now - pendingAt > 2_500) {
            pending = undefined
          }
          return
        }
        const request = read(requestPath)
        if (!validRequest(request) || request.nonce === lastNonce || !sessionIDs.includes(request.sessionID)) return
        const stat = lstatSync(requestPath)
        if (stat.isSymbolicLink() || stat.mtimeMs < now - 3_000 || stat.mtimeMs > now + 1_000) return
        lastNonce = request.nonce
        pending = request
        pendingAt = now
        if (currentSessionID !== request.sessionID) {
          // Navigate exact child sessions; root-session tabs may normalize child IDs.
          context.ui.router.navigate({ type: "session", sessionID: request.sessionID })
        }
      } catch {
        if (!warned) {
          warned = true
          context.ui.toast.show({ message: "Dyland: could not update the terminal route.", variant: "error" })
        }
      }
    }

    tick()
    const timer = setInterval(tick, 250)
    return () => {
      clearInterval(timer)
      for (const file of [path, requestPath, ackPath, terminalPath]) {
        try { unlinkSync(file) } catch {}
      }
    }
  },
})

// Runnable: bun -e 'import { selfCheck } from "./plugin/tui.ts"; selfCheck()'
export function selfCheck() {
  const check = (value: boolean) => { if (!value) throw new Error("Dyland route validation failed") }
  check(validRequest({ sessionID: "ses_test-123", nonce: "12345678-1234-1234-1234-123456789abc" }))
  for (const value of [null, {}, { sessionID: "ses_x", nonce: "../escape" },
    { sessionID: "ses_x\ninput", nonce: "12345678-1234-1234-1234-123456789abc" }]) check(!validRequest(value))
  console.log("Dyland TUI self-check passed")
}
