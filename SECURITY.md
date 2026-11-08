# Security policy

## Reporting a vulnerability

Report suspected vulnerabilities through GitHub's [private vulnerability reporting form](https://github.com/ghulammuzz/dyland/security/advisories/new).
Do not post vulnerabilities, exploit details, credentials, or private session metadata in public issues or pull requests.
If the form is unavailable, do not fall back to publishing sensitive details in a public issue.

Include:

- A clear description of the issue and its potential impact.
- The affected commit or version and your macOS, OpenCode, and Ghostty versions.
- Minimal reproduction steps or a proof of concept using synthetic data.
- Any relevant logs or screenshots, with secrets, session titles, IDs, and personal paths redacted.
- A proposed fix or mitigation, if available.

Keep disclosure private while the report is investigated and a fix is coordinated.
There is no guaranteed response deadline or security service-level agreement.

## Scope

Security-sensitive areas include local bridge and route file permissions, symlink handling, input validation, session verification, Ghostty Automation, and command execution.
Leaks of prompts, answers, permission details, credentials, or other content outside the documented metadata contract are also in scope.
Dyland's local files are not intended to protect metadata from a compromised process running as the same macOS user.

Use the latest source on the repository's default branch when checking whether an issue still reproduces.
Older revisions have no separate security-maintenance commitment.

## Safe diagnostics

Use disposable sessions and synthetic project names when reproducing problems.
Do not upload `~/Library/Application Support/Dyland/`, OpenCode databases, or raw service credentials.
Bridge and route files contain session IDs, titles, directory paths, and routing identifiers even though they exclude prompt and answer bodies.
Only share the minimum redacted evidence needed to reproduce the issue.

For ordinary bugs without a security impact, use the repository's [issue tracker](https://github.com/ghulammuzz/dyland/issues).
