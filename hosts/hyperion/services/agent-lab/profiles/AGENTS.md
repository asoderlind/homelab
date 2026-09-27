# Hyperion Agent Lab Policy

Work is controlled through Linear. Every implementation, review, or operations
task must reference a Linear issue with acceptance criteria and a named human
creator/owner. The human remains accountable and the agent handles the
delegated work. Agents
may create linked Linear child issues for bounded handoffs and may create
branches, commits, and Forgejo pull requests within the access granted by their
role token. Agents never merge, deploy, force-push, alter host configuration,
rotate credentials, delete durable data, or approve their own privileged action.

For all terminal access to Forgejo, use the private service endpoint in
`$FORGEJO_URL` and authenticate API requests with `FORGEJO_TOKEN` without
printing it. Work from the role's existing `agent-wiki` clone and address its
Git remote as `origin` (for example, `git fetch origin` or
`git ls-remote origin`). Never put `forgejo.soderlind.dev` or another public
Forgejo hostname in a shell command. Public HTTPS URLs are for links in issues,
pull requests, and Buzz messages only. Do not use `/api/v1/user` as an
authentication preflight; validate the specific repository, issue, or pull
request endpoint required by the task.

Use the Linear issue identifier at the start of branch names, for example
`ENG-123-fix-timeout`. Every Forgejo pull request must link the authoritative
Linear issue and include its acceptance criteria, verification evidence, risks,
and rollback notes. Do not create a duplicate Forgejo issue merely to authorize
work.

Human approval is required before merges, deployments, destructive changes,
credential changes, repository permission changes, and infrastructure changes.
If approval or credentials are missing, record exactly what is required and stop
safely.

Agent handoffs must create a linked Linear child issue with one target role and
an expected result. Use `linear-agent-bridge handoff` and never print its relay
token. A task may cross role boundaries at most three times; never answer an
agent-only message with another open-ended handoff, and stop immediately if a
handoff begins to loop. Buzz remains a fallback communication surface, but a
Buzz request does not authorize work unless it names the Linear issue.

Linear command approvals are one-time only. Only the configured human owner may
reply `approve once` or `deny`; never request or accept session-wide or permanent
approval. Immutable denial rules still apply even when a human approves.

The `agent-wiki` repository is the shared Obsidian vault and the only shared
durable knowledge surface. Pull with rebase before editing, make small commits,
and push only when the working tree is conflict-free. Never auto-resolve a
conflict: leave the clone intact, report the paths and commits involved, and wait
for a human. Do not put credentials, access tokens, raw private data, transient
chat logs, or unverified speculation in the wiki.
