# Dyland OpenCode bridge

Server plugin pinned to OpenCode V2.1.1.
JavaScript ESM, no build step.
Only direct runtime dependency: `@opencode/plugin@2.1.1`.

## Install

Run `npm ci --prefix plugin` from repository root.
Merge this entry into desired OpenCode `opencode.json(c)` manually:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "plugins": ["/absolute/path/to/dyland/plugin"]
}
```

Reload OpenCode after changing plugin configuration.
No global configuration is changed by this package.
Use managed OpenCode background service for full startup question reconciliation.

## Swift integration

Read `~/Library/Application Support/Dyland/bridge/*.json`.
Filename is first 16 lowercase hex characters of SHA-256 of exact UTF-8 `ctx.location.directory`, followed by `.json`.
Directory mode is `0700`; atomic replacement JSON mode is `0600`.
Ignore dotfiles and files whose `updatedAt` is older than 30 seconds.
No HTTP listener, socket, or command receiver exists for Dyland IPC.

```ts
interface Bridge {
  version: 1
  updatedAt: number // Epoch seconds, fractional precision allowed.
  sessions: { id: string; title: string; directory: string; updatedAt: number }[]
  notices: {
    id: string
    sessionID: string
    kind: "working" | "done" | "question" | "permission" | "error" | "interrupted" | "resolved" | "hook"
    timestamp: number
    requestID?: string
  }[]
  pending: {
    id: string
    sessionID: string
    kind: "question" | "permission"
    timestamp: number
    requestID?: string
  }[]
}
```

Deduplicate notices globally by `id`, not filename or session ID.
Live notices preserve native `event.id` across plugin instances.
Pending identity is `(sessionID, kind, requestID)`; snapshot-only pending entries use native request ID as `id` and create no notification.
Reconcile pending from latest live bridge snapshots, not historical question notices.
Only root sessions are exported, globally across locations, with cursor pagination capped at 200 sessions.
Last 128 notices are retained per writer.
`hook` is reserved; no synthetic hook notices are emitted.

Heartbeat publishes every 10 seconds.
Relevant events publish with a 50 ms coalescing timer; unknown session metadata lookup can add API latency.
Startup and 20-second reconciliation restore pending requests without manufacturing completion notices.
Execution lifecycle events alone produce `working`, `done`, `error`, and `interrupted`.
Step completion, idle state, and historical session outcome never imply completion.
Titles and directory paths are exported; prompt, form fields, answers, resources, errors, and tool bodies are not exported.

Cleanup aborts event subscriptions and snapshot requests and clears all timers.
Final bridge file is deliberately retained for reader TTL expiry, avoiding any conditional-unlink race with another same-location writer.
Concurrent same-location writers use last atomic rename wins; no payload ownership field is added to contract.
All bridge I/O failures are swallowed so notification failures cannot interrupt agent work.

## V2.1.1 API limitation

Installed `@opencode/plugin@2.1.1` exposes `ctx.permission.list`, but neither `ctx.form` nor `ctx.session.form`.
Live native `form.created`, `form.replied`, and `form.cancelled` events work in every server mode.
Question snapshot reconciliation uses the already-running managed service discovered through transitive official `@opencode/client/service`.
Discovery never starts a server.
Requests are restricted to loopback, authenticated through `Service.headers`, and enabled only when `/api/info.pid === process.pid`.
No credentials are written to bridge files.
Standalone and embedded servers without an exposed form-list context cannot restore questions that predate plugin setup or were missed during disconnection.
Permission reconciliation still works there.
Remove this fallback when official plugin context exposes form listing.

## Checks

```sh
npm test --prefix plugin
npm run test:e2e --prefix plugin
```

Unit tests cover lifecycle reduction, privacy, pending reconciliation, pagination, permissions, atomic writes, ownership-safe cleanup, and cancellation.
E2E starts an isolated OpenCode server with temporary project configuration inside `plugin/`, creates a temporary session and form, checks native question/reply events and real bridge JSON, then removes test data.
E2E makes no model calls and edits no global configuration.

Sources: [plugins](https://opencode.ai/v2/docs/build/plugins), [server](https://opencode.ai/v2/docs/build/plugins/server), [client](https://opencode.ai/v2/docs/build/client), installed 2.1.1 schema and plugin adapter definitions.
