/// <reference types="@cloudflare/workers-types" />

import {
  extractSession,
  isRole,
  normalizeActivity,
  roleEnv,
  verifyLinearWebhook,
} from "./core.mjs";

type Role = "coordinator" | "developer" | "ops";

interface Env {
  DB: D1Database;
  PUBLIC_BASE_URL: string;
  LINEAR_OWNER_ID: string;
  TOKEN_ENCRYPTION_KEY: string;
  [key: string]: unknown;
}

const LINEAR_GRAPHQL = "https://api.linear.app/graphql";
const LINEAR_TOKEN = "https://api.linear.app/oauth/token";
const EVENT_RETENTION_SECONDS = 7 * 24 * 60 * 60;
const SESSION_RETENTION_SECONDS = 30 * 24 * 60 * 60;

function json(value: unknown, status = 200): Response {
  return Response.json(value, { status });
}

function envString(env: Env, name: string): string {
  const value = env[name];
  if (typeof value !== "string" || !value) throw new Error(`missing Worker setting ${name}`);
  return value;
}

function bearer(request: Request): string {
  const header = request.headers.get("Authorization") ?? "";
  return header.startsWith("Bearer ") ? header.slice(7) : "";
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function authorizeBridge(request: Request, env: Env, role: Role): Promise<boolean> {
  const supplied = bearer(request);
  if (!supplied) return false;
  const expected = envString(env, roleEnv(role, "BRIDGE_TOKEN"));
  return (await sha256(supplied)) === (await sha256(expected));
}

function toBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function fromBase64(value: string): Uint8Array {
  const binary = atob(value);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

async function encryptionKey(env: Env): Promise<CryptoKey> {
  const raw = fromBase64(envString(env, "TOKEN_ENCRYPTION_KEY"));
  if (raw.byteLength !== 32) throw new Error("TOKEN_ENCRYPTION_KEY must be 32 bytes in base64");
  return crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt", "decrypt"]);
}

async function encrypt(env: Env, plaintext: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encrypted = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    await encryptionKey(env),
    new TextEncoder().encode(plaintext),
  );
  const combined = new Uint8Array(iv.byteLength + encrypted.byteLength);
  combined.set(iv);
  combined.set(new Uint8Array(encrypted), iv.byteLength);
  return toBase64(combined);
}

async function decrypt(env: Env, ciphertext: string): Promise<string> {
  const combined = fromBase64(ciphertext);
  const plaintext = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: combined.slice(0, 12) },
    await encryptionKey(env),
    combined.slice(12),
  );
  return new TextDecoder().decode(plaintext);
}

async function exchangeCode(env: Env, role: Role, code: string): Promise<Record<string, any>> {
  const body = new URLSearchParams({
    grant_type: "authorization_code",
    code,
    redirect_uri: `${env.PUBLIC_BASE_URL}/oauth/${role}/callback`,
    client_id: envString(env, roleEnv(role, "CLIENT_ID")),
    client_secret: envString(env, roleEnv(role, "CLIENT_SECRET")),
  });
  const response = await fetch(LINEAR_TOKEN, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });
  if (!response.ok) throw new Error(`Linear token exchange failed: ${response.status}`);
  return response.json();
}

async function refreshInstallation(env: Env, role: Role, installation: Record<string, any>) {
  const body = new URLSearchParams({
    grant_type: "refresh_token",
    refresh_token: await decrypt(env, installation.refresh_token),
    client_id: envString(env, roleEnv(role, "CLIENT_ID")),
    client_secret: envString(env, roleEnv(role, "CLIENT_SECRET")),
  });
  const response = await fetch(LINEAR_TOKEN, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });
  if (!response.ok) throw new Error(`Linear token refresh failed: ${response.status}`);
  const token = (await response.json()) as Record<string, any>;
  const now = Math.floor(Date.now() / 1000);
  await env.DB.prepare(
    "UPDATE installations SET access_token = ?, refresh_token = ?, expires_at = ?, updated_at = ? WHERE role = ?",
  )
    .bind(
      await encrypt(env, String(token.access_token)),
      await encrypt(env, String(token.refresh_token)),
      now + Number(token.expires_in ?? 86_400),
      now,
      role,
    )
    .run();
  return { ...installation, ...token, access_token: await encrypt(env, String(token.access_token)) };
}

async function accessToken(env: Env, role: Role): Promise<string> {
  let installation = await env.DB.prepare("SELECT * FROM installations WHERE role = ?")
    .bind(role)
    .first<Record<string, any>>();
  if (!installation) throw new Error(`Linear role ${role} is not installed`);
  if (Number(installation.expires_at) <= Math.floor(Date.now() / 1000) + 300) {
    installation = await refreshInstallation(env, role, installation);
  }
  return decrypt(env, String(installation.access_token));
}

async function linearGraphql<T>(env: Env, role: Role, query: string, variables: unknown): Promise<T> {
  const response = await fetch(LINEAR_GRAPHQL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${await accessToken(env, role)}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ query, variables }),
  });
  if (!response.ok) throw new Error(`Linear GraphQL HTTP ${response.status}`);
  const body = (await response.json()) as { data?: T; errors?: Array<{ message: string }> };
  if (body.errors?.length) throw new Error(body.errors.map((error) => error.message).join("; "));
  if (!body.data) throw new Error("Linear GraphQL returned no data");
  return body.data;
}

async function sendActivity(env: Env, role: Role, sessionId: string, content: Record<string, unknown>) {
  const data = await linearGraphql<{ agentActivityCreate: { success: boolean } }>(
    env,
    role,
    `mutation Activity($input: AgentActivityCreateInput!) {
      agentActivityCreate(input: $input) { success }
    }`,
    { input: { agentSessionId: sessionId, content: normalizeActivity(content) } },
  );
  if (!data.agentActivityCreate.success) throw new Error("Linear rejected agent activity");
}

async function handleInstall(request: Request, env: Env, role: Role): Promise<Response> {
  const state = crypto.randomUUID();
  const now = Math.floor(Date.now() / 1000);
  await env.DB.prepare("INSERT INTO oauth_states (state, role, created_at) VALUES (?, ?, ?)")
    .bind(state, role, now)
    .run();
  const url = new URL("https://linear.app/oauth/authorize");
  url.searchParams.set("response_type", "code");
  url.searchParams.set("client_id", envString(env, roleEnv(role, "CLIENT_ID")));
  url.searchParams.set("redirect_uri", `${env.PUBLIC_BASE_URL}/oauth/${role}/callback`);
  url.searchParams.set("scope", "read,write,app:assignable,app:mentionable");
  url.searchParams.set("actor", "app");
  url.searchParams.set("state", state);
  return Response.redirect(url.toString(), 302);
}

async function handleCallback(request: Request, env: Env, role: Role): Promise<Response> {
  const url = new URL(request.url);
  const state = url.searchParams.get("state") ?? "";
  const code = url.searchParams.get("code") ?? "";
  const stored = await env.DB.prepare("SELECT role, created_at FROM oauth_states WHERE state = ?")
    .bind(state)
    .first<{ role: string; created_at: number }>();
  await env.DB.prepare("DELETE FROM oauth_states WHERE state = ?").bind(state).run();
  const now = Math.floor(Date.now() / 1000);
  if (!stored || stored.role !== role || now - stored.created_at > 600 || !code) {
    return json({ error: "invalid or expired OAuth state" }, 400);
  }
  const token = await exchangeCode(env, role, code);
  const viewer = await fetch(LINEAR_GRAPHQL, {
    method: "POST",
    headers: { Authorization: `Bearer ${token.access_token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ query: "query { viewer { id organization { id } } }" }),
  });
  const viewerBody = (await viewer.json()) as any;
  const appUserId = viewerBody.data?.viewer?.id;
  const workspaceId = viewerBody.data?.viewer?.organization?.id;
  if (!viewer.ok || !appUserId || !workspaceId) throw new Error("could not resolve Linear app identity");
  await env.DB.prepare(
    `INSERT INTO installations
      (role, workspace_id, app_user_id, access_token, refresh_token, expires_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(role) DO UPDATE SET workspace_id=excluded.workspace_id,
       app_user_id=excluded.app_user_id, access_token=excluded.access_token,
       refresh_token=excluded.refresh_token, expires_at=excluded.expires_at,
       updated_at=excluded.updated_at`,
  )
    .bind(
      role,
      workspaceId,
      appUserId,
      await encrypt(env, String(token.access_token)),
      await encrypt(env, String(token.refresh_token)),
      now + Number(token.expires_in ?? 86_400),
      now,
    )
    .run();
  return new Response(`Installed Hyperion ${role} in Linear workspace ${workspaceId}.`, {
    headers: { "Content-Type": "text/plain; charset=utf-8" },
  });
}

async function handleWebhook(request: Request, env: Env, role: Role, ctx: ExecutionContext) {
  const rawBody = await request.arrayBuffer();
  const valid = await verifyLinearWebhook(
    envString(env, roleEnv(role, "WEBHOOK_SECRET")),
    rawBody,
    request.headers.get("Linear-Signature") ?? "",
    request.headers.get("Linear-Timestamp") ?? "",
  );
  if (!valid) return json({ error: "invalid webhook signature or timestamp" }, 401);
  const deliveryId = request.headers.get("Linear-Delivery") ?? "";
  if (!deliveryId) return json({ error: "missing Linear-Delivery" }, 400);
  const payload = JSON.parse(new TextDecoder().decode(rawBody)) as Record<string, any>;
  const session = extractSession(payload);
  if (!session) return json({ ignored: true });
  const now = Math.floor(Date.now() / 1000);
  const inserted = await env.DB.prepare(
    `INSERT OR IGNORE INTO inbox
      (delivery_id, role, linear_session_id, action, payload_json, available_at, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(deliveryId, role, session.id, session.action, JSON.stringify(payload), now, now)
    .run();
  if (inserted.meta.changes > 0 && session.action === "created") {
    ctx.waitUntil(
      sendActivity(env, role, session.id, {
        type: "thought",
        body: `Hyperion ${role} received this task and queued it for secure execution.`,
      }),
    );
  }
  return json({ accepted: true, duplicate: inserted.meta.changes === 0 });
}

async function handleLease(env: Env, role: Role): Promise<Response> {
  const now = Math.floor(Date.now() / 1000);
  const event = await env.DB.prepare(
    `SELECT delivery_id, linear_session_id, action, payload_json, attempts
       FROM inbox
      WHERE role = ? AND available_at <= ?
        AND (state = 'queued' OR (state = 'leased' AND leased_until < ?))
      ORDER BY created_at ASC LIMIT 1`,
  )
    .bind(role, now, now)
    .first<Record<string, any>>();
  if (!event) return new Response(null, { status: 204 });
  await env.DB.prepare(
    "UPDATE inbox SET state='leased', leased_until=?, attempts=attempts+1 WHERE delivery_id=?",
  )
    .bind(now + 90, event.delivery_id)
    .run();
  return json({
    deliveryId: event.delivery_id,
    linearSessionId: event.linear_session_id,
    action: event.action,
    payload: JSON.parse(event.payload_json),
    attempt: Number(event.attempts) + 1,
    ownerId: env.LINEAR_OWNER_ID,
  });
}

async function handleAck(request: Request, env: Env, role: Role, deliveryId: string) {
  const body = (await request.json()) as { status?: string; error?: string; retryAfterSeconds?: number };
  const now = Math.floor(Date.now() / 1000);
  if (body.status === "retry") {
    const delay = Math.min(Math.max(Number(body.retryAfterSeconds ?? 10), 1), 3600);
    await env.DB.prepare(
      "UPDATE inbox SET state='queued', available_at=?, leased_until=NULL, last_error=? WHERE delivery_id=? AND role=?",
    )
      .bind(now + delay, String(body.error ?? "retry requested").slice(0, 1000), deliveryId, role)
      .run();
  } else {
    await env.DB.prepare(
      "UPDATE inbox SET state='complete', completed_at=?, leased_until=NULL, last_error=? WHERE delivery_id=? AND role=?",
    )
      .bind(now, body.error ? String(body.error).slice(0, 1000) : null, deliveryId, role)
      .run();
  }
  return json({ success: true });
}

async function handleSessionState(request: Request, env: Env, role: Role, sessionId: string) {
  if (request.method === "GET") {
    const row = await env.DB.prepare("SELECT * FROM sessions WHERE linear_session_id=? AND role=?")
      .bind(sessionId, role)
      .first();
    return json(row ?? {});
  }
  const body = (await request.json()) as Record<string, any>;
  const now = Math.floor(Date.now() / 1000);
  await env.DB.prepare(
    `INSERT INTO sessions
      (linear_session_id, role, hermes_session_id, active_run_id, approval_requested_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?)
     ON CONFLICT(linear_session_id) DO UPDATE SET
       hermes_session_id=COALESCE(excluded.hermes_session_id, sessions.hermes_session_id),
       active_run_id=excluded.active_run_id,
       approval_requested_at=excluded.approval_requested_at,
       updated_at=excluded.updated_at`,
  )
    .bind(
      sessionId,
      role,
      body.hermesSessionId ?? null,
      body.activeRunId ?? null,
      body.approvalRequestedAt ?? null,
      now,
    )
    .run();
  return json({ success: true });
}

async function handleHandoff(request: Request, env: Env, role: Role) {
  const body = (await request.json()) as {
    parentIssueId?: string;
    targetRole?: string;
    title?: string;
    description?: string;
  };
  const targetRole = String(body.targetRole ?? "");
  if (!isRole(targetRole) || targetRole === role) {
    return json({ error: "targetRole must name a different Hyperion role" }, 400);
  }
  const parentIssueId = String(body.parentIssueId ?? "").trim();
  const title = String(body.title ?? "").trim().slice(0, 255);
  if (!parentIssueId || !title) return json({ error: "parentIssueId and title are required" }, 400);
  const target = await env.DB.prepare("SELECT app_user_id FROM installations WHERE role = ?")
    .bind(targetRole)
    .first<{ app_user_id: string }>();
  if (!target?.app_user_id) return json({ error: `target role ${targetRole} is not installed` }, 409);
  const parent = await linearGraphql<{
    issue: {
      id: string;
      team: { id: string };
      project?: { id: string };
      assignee?: { id: string };
    } | null;
  }>(
    env,
    role,
    `query ParentIssue($id: String!) {
      issue(id: $id) { id team { id } project { id } assignee { id } }
    }`,
    { id: parentIssueId },
  );
  if (!parent.issue) return json({ error: "parent issue not found" }, 404);
  const created = await linearGraphql<{
    issueCreate: { success: boolean; issue?: { id: string; identifier: string; url: string } };
  }>(
    env,
    role,
    `mutation CreateHandoff($input: IssueCreateInput!) {
      issueCreate(input: $input) { success issue { id identifier url } }
    }`,
    {
      input: {
        teamId: parent.issue.team.id,
        parentId: parent.issue.id,
        projectId: parent.issue.project?.id,
        assigneeId: parent.issue.assignee?.id,
        title,
        description: String(body.description ?? "").slice(0, 20_000),
      },
    },
  );
  if (!created.issueCreate.success || !created.issueCreate.issue) {
    throw new Error("Linear did not create the handoff issue");
  }
  const issue = created.issueCreate.issue;
  const delegated = await linearGraphql<{ issueUpdate: { success: boolean } }>(
    env,
    role,
    `mutation DelegateHandoff($id: String!, $input: IssueUpdateInput!) {
      issueUpdate(id: $id, input: $input) { success }
    }`,
    { id: issue.id, input: { delegateId: target.app_user_id } },
  );
  if (!delegated.issueUpdate.success) throw new Error("created child issue but could not delegate it");
  return json({ success: true, issue, targetRole });
}

async function handleInternal(request: Request, env: Env, role: Role, segments: string[]) {
  if (!(await authorizeBridge(request, env, role))) return json({ error: "unauthorized" }, 401);
  if (request.method === "POST" && segments[0] === "lease") return handleLease(env, role);
  if (request.method === "POST" && segments[0] === "handoffs") return handleHandoff(request, env, role);
  if (request.method === "POST" && segments[0] === "events" && segments[2] === "ack") {
    return handleAck(request, env, role, segments[1]);
  }
  if (segments[0] === "sessions" && segments[1]) {
    const sessionId = decodeURIComponent(segments[1]);
    if (segments.length === 2 && ["GET", "PUT"].includes(request.method)) {
      return handleSessionState(request, env, role, sessionId);
    }
    if (request.method === "POST" && segments[2] === "activity") {
      const body = (await request.json()) as Record<string, unknown>;
      await sendActivity(env, role, sessionId, body);
      return json({ success: true });
    }
    if (request.method === "POST" && segments[2] === "external-urls") {
      const body = (await request.json()) as { externalUrls?: Array<{ label: string; url: string }> };
      const urls = (body.externalUrls ?? []).slice(0, 10).map((entry) => ({
        label: String(entry.label).slice(0, 80),
        url: String(entry.url),
      }));
      const data = await linearGraphql<{ agentSessionUpdate: { success: boolean } }>(
        env,
        role,
        `mutation UpdateSession($id: String!, $input: AgentSessionUpdateInput!) {
          agentSessionUpdate(id: $id, input: $input) { success }
        }`,
        { id: sessionId, input: { externalUrls: urls } },
      );
      return json({ success: data.agentSessionUpdate.success });
    }
  }
  return json({ error: "not found" }, 404);
}

async function cleanup(env: Env) {
  const now = Math.floor(Date.now() / 1000);
  await env.DB.batch([
    env.DB.prepare("DELETE FROM oauth_states WHERE created_at < ?").bind(now - 600),
    env.DB.prepare("DELETE FROM inbox WHERE state='complete' AND completed_at < ?").bind(
      now - EVENT_RETENTION_SECONDS,
    ),
    env.DB.prepare("DELETE FROM sessions WHERE active_run_id IS NULL AND updated_at < ?").bind(
      now - SESSION_RETENTION_SECONDS,
    ),
  ]);
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    try {
      const url = new URL(request.url);
      const segments = url.pathname.split("/").filter(Boolean);
      if (url.pathname === "/health") return json({ status: "ok" });
      const role = segments[1] ?? "";
      if (!isRole(role)) return json({ error: "unknown role" }, 404);
      if (request.method === "GET" && segments[0] === "install") return handleInstall(request, env, role);
      if (request.method === "GET" && segments[0] === "oauth" && segments[2] === "callback") {
        return handleCallback(request, env, role);
      }
      if (request.method === "POST" && segments[0] === "webhooks") {
        return handleWebhook(request, env, role, ctx);
      }
      if (segments[0] === "internal") return handleInternal(request, env, role, segments.slice(2));
      return json({ error: "not found" }, 404);
    } catch (error) {
      console.error(error);
      return json({ error: error instanceof Error ? error.message : "internal error" }, 500);
    } finally {
      ctx.waitUntil(cleanup(env));
    }
  },
} satisfies ExportedHandler<Env>;
