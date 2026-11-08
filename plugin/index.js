import { Plugin } from "@opencode/plugin"
import { startBridge } from "./runtime.js"

export default Plugin.define({
  id: "dyland.bridge",
  setup(ctx) {
    try { return startBridge(ctx) } catch { /* Notifications must never block OpenCode. */ }
  },
})
