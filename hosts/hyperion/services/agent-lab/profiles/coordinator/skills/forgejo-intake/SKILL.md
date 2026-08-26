---
name: linear-intake
description: Refine an authoritative Linear issue and route bounded child issues to one lab role.
---

# Linear intake

Follow the Linear authority and Forgejo command-routing policy in the workspace
`AGENTS.md`. The current Linear Agent Session supplies the authoritative issue
context. Use `$FORGEJO_URL` plus the role token only when repository inspection
is required; never use a public Forgejo hostname in a terminal command or call
`/api/v1/user` as an authentication preflight.

Before handing work off, confirm the Linear issue records the request, scope,
acceptance criteria, verification expectations, risks, and human assignee. Use
`linear-agent-bridge handoff --target ROLE --parent ISSUE --title TITLE
--description DESCRIPTION` to create one linked child issue and delegate it to
exactly one next role. State the artifact it should return. Do not create an
implementation branch or merge a pull request. If the request needs deployment,
credentials, deletion, or host changes, mark it blocked on human approval.
