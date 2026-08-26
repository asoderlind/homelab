export const ROLES = ["coordinator", "developer", "ops"];

export function isRole(value) {
  return ROLES.includes(value);
}

export function roleEnv(role, suffix) {
  return `${role.toUpperCase()}_${suffix}`;
}

export function bytesToHex(bytes) {
  return [...new Uint8Array(bytes)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export function constantTimeEqual(left, right) {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

export async function linearSignature(secret, rawBody) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return bytesToHex(await crypto.subtle.sign("HMAC", key, rawBody));
}

export async function verifyLinearWebhook(secret, rawBody, signature, timestamp, nowMs = Date.now()) {
  const parsedTimestamp = Number(timestamp);
  if (!Number.isFinite(parsedTimestamp) || Math.abs(nowMs - parsedTimestamp) > 60_000) {
    return false;
  }
  const expected = await linearSignature(secret, rawBody);
  return constantTimeEqual(signature.toLowerCase(), expected);
}

export function extractSession(payload) {
  const session = payload.agentSession ?? payload.data?.agentSession;
  const id = session?.id;
  if (!id || typeof id !== "string") return null;
  const action = String(payload.action ?? payload.data?.action ?? "created");
  const promptContext = String(
    payload.promptContext ?? payload.data?.promptContext ?? session.promptContext ?? "",
  );
  const activity = payload.agentActivity ?? payload.data?.agentActivity;
  const actorId = String(
    activity?.creator?.id ?? activity?.user?.id ?? payload.actor?.id ?? payload.data?.actor?.id ?? "",
  );
  return { id, action, promptContext, actorId };
}

export function normalizeActivity(content) {
  const type = String(content.type ?? "");
  if (!["thought", "elicitation", "action", "response", "error"].includes(type)) {
    throw new Error(`unsupported activity type: ${type}`);
  }
  if (type === "action") {
    return {
      type,
      action: String(content.action ?? "Working"),
      parameter: String(content.parameter ?? ""),
      ...(content.result === undefined ? {} : { result: String(content.result) }),
    };
  }
  return { type, body: String(content.body ?? "") };
}
