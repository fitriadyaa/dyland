# Contributing to Dyland

Focused bug reports and pull requests are welcome.
Discuss larger behavior changes in an issue before starting substantial work.

## Prerequisites

- Apple Silicon Mac running macOS 14 or later.
- Swift 6 and a compatible macOS SDK from Xcode or Xcode Command Line Tools.
- Node.js 24 or later, npm, and Git.
- OpenCode V2, tested with 2.1.1.
- Ghostty 1.3 or later with AppleScript enabled for manual session-routing checks.

Clone `https://github.com/ghulammuzz/dyland.git` and run commands from the repository root.
Install locked dependencies before testing:

```sh
npm ci --prefix plugin --ignore-scripts
```

## Changes and validation

Keep changes small and consistent with the existing SwiftUI, AppKit, and JavaScript code.
Prefer native APIs and existing dependencies over new infrastructure.
For a bug fix, reproduce the end-user failure first and leave a runnable regression check for nontrivial logic.
Do not manually edit generated files or dependency lockfiles without the corresponding dependency change.

Run before submitting:

```sh
/bin/zsh ./build.sh
./dist/Dyland.app/Contents/MacOS/Dyland --self-check
npm test --prefix plugin
npm run test:e2e --prefix plugin
```

The build includes ad-hoc signing and runs the app self-check.
E2E tests require the `opencode` executable and start an isolated service with temporary sessions and forms.
They make no model calls and do not modify global OpenCode configuration.

For UI or routing changes, also open `dist/Dyland.app` and check **Preview Island**, hover and dismissal, session selection, pending requests, and exact-session opening in Ghostty.
Check Reduce Motion and both notched and regular displays when applicable.
Do not restart an OpenCode service while agents are working.
Mention any validation you could not run and why.

## Pull requests and bug reports

Describe the problem, reproduction steps, expected behavior, and actual behavior.
Include relevant macOS, Swift, Node.js, OpenCode, and Ghostty versions.
For pull requests, summarize the change and list validation results.
For UI changes, include screenshots with private metadata removed.
Keep every complete sentence on its own physical line in Markdown documentation.

## Privacy and security

Preserve the metadata-only bridge contract and private file permissions.
Do not add prompts, answers, form fields, permission details, tool output, error bodies, or credentials to bridge or routing files.
Validate data read from local files and external processes; do not weaken exact-session routing checks.
Never commit local bridge data, credentials, personal paths, session metadata, or unredacted diagnostics.
Report vulnerabilities privately using [SECURITY.md](SECURITY.md), not a public issue or pull request.

## License

By submitting a contribution, you agree that it can be distributed under the repository's [MIT license](LICENSE).
Only contribute code and assets you have the right to license this way.
The bundled `dyland-sound.mp3` is also distributed under MIT.
