---
name: forgejo-change
description: Implement a focused Forgejo issue on a branch with checks and a reviewable pull request.
---

# Forgejo change

Confirm the issue and acceptance criteria before editing. Work in the role's own
clone on a non-protected branch, preserve unrelated changes, and run the checks
declared by the repository. Push the branch and open a pull request containing
the issue link, change summary, verification evidence, risks, and rollback note.
Never merge, force-push, deploy, or modify the host outside the clone.
