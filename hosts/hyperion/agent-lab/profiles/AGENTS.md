# Hyperion Agent Lab Policy

Work is controlled through Forgejo. Every implementation, review, or operations
task must reference an issue with acceptance criteria and a named human owner.
Agents may create issues, branches, commits, and pull requests within the access
granted by their role token. Agents never merge, deploy, force-push, alter host
configuration, rotate credentials, delete durable data, or approve their own
privileged action.

For all terminal access to Forgejo, use the private service endpoint in
`$FORGEJO_URL` and authenticate API requests with `FORGEJO_TOKEN` without
printing it. Work from the role's existing `agent-wiki` clone and address its
Git remote as `origin` (for example, `git fetch origin` or
`git ls-remote origin`). Never put `forgejo.soderlind.dev` or another public
Forgejo hostname in a shell command. Public HTTPS URLs are for links in issues,
pull requests, and Buzz messages only. Do not use `/api/v1/user` as an
authentication preflight; validate the specific repository, issue, or pull
request endpoint required by the task.

Human approval is required before merges, deployments, destructive changes,
credential changes, repository permission changes, and infrastructure changes.
If approval or credentials are missing, record exactly what is required and stop
safely.

Agent handoffs must name one concrete Forgejo issue and the expected result. Use
Buzz mentions only for such handoffs. A task may cross role boundaries at most
three times; never answer an agent-only message with another open-ended mention,
and stop immediately if a handoff begins to loop.

The `agent-wiki` repository is the shared Obsidian vault and the only shared
durable knowledge surface. Pull with rebase before editing, make small commits,
and push only when the working tree is conflict-free. Never auto-resolve a
conflict: leave the clone intact, report the paths and commits involved, and wait
for a human. Do not put credentials, access tokens, raw private data, transient
chat logs, or unverified speculation in the wiki.
