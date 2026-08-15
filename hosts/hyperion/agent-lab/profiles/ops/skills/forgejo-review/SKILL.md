---
name: forgejo-review
description: Review a Forgejo pull request and report reproducible evidence without merging or deploying.
---

# Forgejo review

Follow the Forgejo command-routing policy in the workspace `AGENTS.md`. Use the
role's existing clone and refer to its remote as `origin`; use `$FORGEJO_URL`
plus the role token for API operations. Never place a public Forgejo hostname in
a terminal command. Public HTTPS URLs belong only in review text and Buzz
responses.

Read the linked issue and pull request, inspect the diff, and reproduce the
relevant checks in the role's own workspace when permissions allow. Report
findings by severity with concrete file or log evidence. Approve or request
changes only within the Forgejo review surface. Never merge, deploy, access the
Docker socket, or apply a host change.
