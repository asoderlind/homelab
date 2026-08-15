---
name: forgejo-review
description: Review a Forgejo pull request and report reproducible evidence without merging or deploying.
---

# Forgejo review

Read the linked issue and pull request, inspect the diff, and reproduce the
relevant checks in the role's own workspace when permissions allow. Report
findings by severity with concrete file or log evidence. Approve or request
changes only within the Forgejo review surface. Never merge, deploy, access the
Docker socket, or apply a host change.
