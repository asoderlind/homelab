---
name: linear-forgejo-change
description: Implement an authoritative Linear issue on a Forgejo branch with checks and a reviewable pull request.
---

# Forgejo change

Follow the Forgejo command-routing policy in the workspace `AGENTS.md`. Enter
the role's existing `agent-wiki` clone before running Git commands and use
`origin` for remote operations such as `git fetch origin` and
`git ls-remote origin`. Use `$FORGEJO_URL` plus the role token for API
operations. Never place a public Forgejo hostname in a terminal command; public
HTTPS URLs belong only in pull-request metadata and Buzz responses.

Confirm the Linear issue, human owner, and acceptance criteria before editing.
Work in the role's own clone on a non-protected branch beginning with the Linear
identifier, preserve unrelated changes, and run the checks declared by the
repository. Push the branch and open a pull request containing the Linear issue
link, change summary, verification evidence, risks, and rollback note. Never
merge, force-push, deploy, or modify the host outside the clone.
