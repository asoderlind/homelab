---
name: forgejo-intake
description: Turn a Buzz request into a bounded Forgejo issue and route it to one lab role.
---

# Forgejo intake

Follow the Forgejo command-routing policy in the workspace `AGENTS.md`. Use
`$FORGEJO_URL` plus the role token for API operations. Never use a public
Forgejo hostname in a terminal command or call `/api/v1/user` as an
authentication preflight; check the target repository or issue endpoint
directly. Public HTTPS URLs belong only in the issue and Buzz response.

Before handing work off, locate or create one Forgejo issue. Record the request,
scope, acceptance criteria, verification expectations, risks, and human owner.
Link the issue in the Buzz thread. Assign exactly one next role and state the
artifact it should return. Do not create an implementation branch or merge a
pull request. If the request needs deployment, credentials, deletion, or host
changes, mark it blocked on human approval.
