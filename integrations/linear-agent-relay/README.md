# Hyperion Linear agent relay

This Cloudflare Worker is the only public component of the Hyperion Linear
integration. It validates Linear webhooks, stores them in D1, owns the three
Linear app OAuth tokens, and exposes a narrow authenticated mailbox to the
outbound-only bridges on Hyperion. It never accepts a connection to Hyperion.

The Linear Agents API is a developer preview. Keep the GraphQL operations in
`src/index.ts` isolated here and run the tests after reviewing Linear schema
changes.

## Provision Cloudflare

From this directory, authenticate Wrangler and create the database:

```sh
npx wrangler login
npx wrangler d1 create linear-agent-relay
```

Copy the returned database ID into `wrangler.toml`, set `PUBLIC_BASE_URL` to the
final Worker URL, and set `LINEAR_OWNER_ID` to the one human allowed to approve
commands. Apply the schema:

```sh
npm install
npm test
npm run db:migrate:remote
```

Generate a 32-byte base64 encryption key and put it directly into Wrangler;
never commit it:

```sh
openssl rand -base64 32 | npx wrangler secret put TOKEN_ENCRYPTION_KEY
```

## Create the Linear agents

Create three OAuth applications in Linear named `Hyperion Coordinator`,
`Hyperion Developer`, and `Hyperion Ops`. For each application:

- use `https://WORKER/oauth/ROLE/callback` as its redirect URL;
- use `https://WORKER/webhooks/ROLE` as its webhook URL;
- enable Agent session events;
- install with `read`, `write`, `app:assignable`, and `app:mentionable` scopes;
- do not grant admin, customer, or initiative scopes.

Put the client ID, client secret, webhook signing secret, and a separately
generated bridge token into Worker secrets. Repeat the commands for
`COORDINATOR`, `DEVELOPER`, and `OPS`:

```sh
npx wrangler secret put COORDINATOR_CLIENT_ID
npx wrangler secret put COORDINATOR_CLIENT_SECRET
npx wrangler secret put COORDINATOR_WEBHOOK_SECRET
npx wrangler secret put COORDINATOR_BRIDGE_TOKEN
```

Deploy, then visit each installation URL as a Linear workspace administrator:

```sh
npm run deploy
open https://WORKER/install/coordinator
open https://WORKER/install/developer
open https://WORKER/install/ops
```

The three bridge-token values must also be placed in the matching Hyperion role
environment files. OAuth access and refresh tokens remain encrypted in D1 and
are never copied to Hyperion.

## Hyperion secrets and checks

Edit `/var/lib/agent-lab/secrets/{coordinator,developer,ops}.env` as root. Add a
unique Hermes API key and the matching Worker bridge token to each file:

```ini
LINEAR_RELAY_URL=https://WORKER
LINEAR_RELAY_TOKEN=replace-with-this-roles-worker-secret
API_SERVER_KEY=replace-with-a-separate-random-key
```

`buzz-bootstrap` preserves these fields on later runs. Deploy Hyperion after all
three files are ready, then verify:

```sh
sudo systemctl status agent-lab-{coordinator,developer,ops}
sudo systemctl status agent-lab-linear-{coordinator,developer,ops}
curl https://WORKER/health
```

Assign a human owner to a Linear issue, then delegate it to each Hyperion agent.
Verify progress activities, a follow-up prompt, `approve once`, `deny`, a linked
Forgejo pull request, and delivery of a queued event after restarting one bridge.

## Security and recovery

- Linear webhook signatures cover the raw body and requests older than one
  minute are rejected.
- `Linear-Delivery` is the idempotency key. A lease expires after 90 seconds and
  can be retried without launching duplicate acknowledged work.
- Each Hyperion bridge token can access only its own role. Internal endpoints
  expose session activities and bounded child-issue handoffs, not arbitrary
  Linear GraphQL.
- Only the configured `LINEAR_OWNER_ID` can answer an approval, and the bridge
  maps only `approve once` and `deny`.
- Completed events are retained for seven days; inactive session mappings are
  retained for thirty days. Back up D1 if queued work must survive loss of the
  Cloudflare account.
