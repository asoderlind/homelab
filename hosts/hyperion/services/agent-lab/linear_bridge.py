#!/usr/bin/env python3
"""Outbound-only bridge between Linear Agent Sessions and a local Hermes gateway."""

from __future__ import annotations

import hashlib
import argparse
import json
import logging
import os
import re
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any, Iterator


LOG = logging.getLogger("linear-agent-bridge")
ROLES = {"coordinator", "developer", "ops"}
APPROVE_ONCE = {"approve", "approve once", "allow", "allow once"}
DENY = {"deny", "reject"}
STOP = {"stop", "/stop", "cancel", "cancel run"}
FORGEJO_PULL_RE = re.compile(r"https://forgejo\.soderlind\.dev/[^\s)>]+/pulls/\d+")


class BridgeError(RuntimeError):
    pass


class RetryableError(BridgeError):
    pass


def nested(payload: dict[str, Any], *paths: tuple[str, ...]) -> Any:
    for path in paths:
        value: Any = payload
        for key in path:
            if not isinstance(value, dict) or key not in value:
                break
            value = value[key]
        else:
            return value
    return None


def session_payload(payload: dict[str, Any]) -> dict[str, Any]:
    value = nested(payload, ("agentSession",), ("data", "agentSession"))
    return value if isinstance(value, dict) else {}


def prompt_text(payload: dict[str, Any]) -> str:
    action = str(nested(payload, ("action",), ("data", "action")) or "created")
    if action == "prompted":
        value = nested(
            payload,
            ("agentActivity", "body"),
            ("data", "agentActivity", "body"),
            ("agentActivity", "content", "body"),
            ("data", "agentActivity", "content", "body"),
        )
    else:
        value = nested(
            payload,
            ("promptContext",),
            ("data", "promptContext"),
            ("agentSession", "promptContext"),
            ("data", "agentSession", "promptContext"),
        )
    return str(value or "").strip()


def actor_id(payload: dict[str, Any]) -> str:
    return str(
        nested(
            payload,
            ("agentActivity", "creator", "id"),
            ("data", "agentActivity", "creator", "id"),
            ("agentActivity", "user", "id"),
            ("data", "agentActivity", "user", "id"),
            ("actor", "id"),
            ("data", "actor", "id"),
            ("agentSession", "creatorId"),
            ("data", "agentSession", "creatorId"),
            ("agentSession", "creator", "id"),
            ("data", "agentSession", "creator", "id"),
        )
        or ""
    )


def has_human_owner(payload: dict[str, Any]) -> bool:
    session = session_payload(payload)
    creator = session.get("creator") if isinstance(session.get("creator"), dict) else {}
    creator_id = str(session.get("creatorId") or creator.get("id") or "")
    app_user_id = str(session.get("appUserId") or payload.get("appUserId") or "")
    if creator_id:
        return creator_id != app_user_id and not bool(creator.get("isApp") or creator.get("isBot"))
    issue = session.get("issue") if isinstance(session.get("issue"), dict) else {}
    assignee = issue.get("assignee") if isinstance(issue, dict) else None
    if isinstance(assignee, dict) and assignee.get("id"):
        return not bool(assignee.get("isApp") or assignee.get("isBot"))
    context = prompt_text(payload)
    return "<assignee" in context and (" id=" in context or " name=" in context)


def human_owner(payload: dict[str, Any]) -> str:
    session = session_payload(payload)
    creator = session.get("creator") if isinstance(session.get("creator"), dict) else {}
    return str(
        creator.get("name")
        or creator.get("displayName")
        or session.get("creatorId")
        or creator.get("id")
        or ""
    )


def stable_hermes_session(role: str, linear_session_id: str) -> str:
    digest = hashlib.sha256(f"{role}:{linear_session_id}".encode()).hexdigest()[:32]
    return f"linear_{role}_{digest}"


def parse_sse(lines: Iterator[bytes]) -> Iterator[dict[str, Any]]:
    data: list[str] = []
    event_name = ""
    for raw_line in lines:
        line = raw_line.decode("utf-8", errors="replace").rstrip("\r\n")
        if not line:
            if data:
                event = json.loads("\n".join(data))
                if event_name and "event" not in event:
                    event["event"] = event_name
                yield event
            data = []
            event_name = ""
        elif line.startswith("event:"):
            event_name = line[6:].strip()
        elif line.startswith("data:"):
            data.append(line[5:].strip())
    if data:
        event = json.loads("\n".join(data))
        if event_name and "event" not in event:
            event["event"] = event_name
        yield event


@dataclass(frozen=True)
class Config:
    role: str
    relay_url: str
    relay_token: str
    hermes_url: str
    hermes_key: str
    poll_seconds: float = 2.0
    approval_timeout_seconds: int = 900

    @classmethod
    def from_env(cls, *, require_hermes: bool = True) -> "Config":
        role = os.environ.get("LINEAR_AGENT_ROLE", "")
        if role not in ROLES:
            raise BridgeError("LINEAR_AGENT_ROLE must be coordinator, developer, or ops")
        port = int(os.environ.get("API_SERVER_PORT", "0"))
        hermes_key = os.environ.get("API_SERVER_KEY", "")
        if require_hermes and not hermes_key:
            raise BridgeError("API_SERVER_KEY is required for the polling bridge")
        return cls(
            role=role,
            relay_url=os.environ["LINEAR_RELAY_URL"].rstrip("/"),
            relay_token=os.environ["LINEAR_RELAY_TOKEN"],
            hermes_url=f"http://127.0.0.1:{port}",
            hermes_key=hermes_key,
            poll_seconds=float(os.environ.get("LINEAR_POLL_SECONDS", "2")),
            approval_timeout_seconds=int(os.environ.get("LINEAR_APPROVAL_TIMEOUT_SECONDS", "900")),
        )


class Bridge:
    def __init__(self, config: Config):
        self.config = config
        self._pending_approvals: dict[str, tuple[str, float]] = {}
        self._lock = threading.Lock()

    def _request(
        self,
        base: str,
        path: str,
        *,
        token: str,
        method: str = "GET",
        body: dict[str, Any] | None = None,
        timeout: float = 30,
    ) -> tuple[int, dict[str, Any]]:
        data = None if body is None else json.dumps(body).encode()
        request = urllib.request.Request(
            f"{base}{path}",
            method=method,
            data=data,
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
                "User-Agent": f"hyperion-linear-{self.config.role}/1",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                raw = response.read()
                return response.status, json.loads(raw) if raw else {}
        except urllib.error.HTTPError as error:
            raw = error.read()
            details = raw.decode("utf-8", errors="replace")
            if error.code in {408, 409, 425, 429, 500, 502, 503, 504}:
                raise RetryableError(f"HTTP {error.code}: {details[:500]}") from error
            raise BridgeError(f"HTTP {error.code}: {details[:500]}") from error
        except (urllib.error.URLError, TimeoutError) as error:
            raise RetryableError(str(error)) from error

    def relay(self, path: str, *, method: str = "GET", body: dict[str, Any] | None = None):
        return self._request(
            self.config.relay_url,
            f"/internal/{self.config.role}{path}",
            token=self.config.relay_token,
            method=method,
            body=body,
        )

    def hermes(self, path: str, *, method: str = "GET", body: dict[str, Any] | None = None):
        return self._request(
            self.config.hermes_url,
            path,
            token=self.config.hermes_key,
            method=method,
            body=body,
        )

    def activity(self, linear_session_id: str, activity_type: str, **content: Any) -> None:
        self.relay(
            f"/sessions/{urllib.parse.quote(linear_session_id, safe='')}/activity",
            method="POST",
            body={"type": activity_type, **content},
        )

    def session_state(self, linear_session_id: str) -> dict[str, Any]:
        return self.relay(
            f"/sessions/{urllib.parse.quote(linear_session_id, safe='')}", method="GET"
        )[1]

    def update_session(self, linear_session_id: str, **state: Any) -> None:
        self.relay(
            f"/sessions/{urllib.parse.quote(linear_session_id, safe='')}",
            method="PUT",
            body=state,
        )

    def acknowledge(self, delivery_id: str, *, retry: bool = False, error: str = "") -> None:
        body: dict[str, Any] = {"status": "retry" if retry else "complete"}
        if error:
            body["error"] = error
        if retry:
            body["retryAfterSeconds"] = 10
        self.relay(f"/events/{urllib.parse.quote(delivery_id, safe='')}/ack", method="POST", body=body)

    def _open_run_events(self, run_id: str):
        request = urllib.request.Request(
            f"{self.config.hermes_url}/v1/runs/{urllib.parse.quote(run_id, safe='')}/events",
            headers={"Authorization": f"Bearer {self.config.hermes_key}"},
        )
        return urllib.request.urlopen(request, timeout=3600)

    def start_run(self, linear_session_id: str, text: str, owner: str = "") -> str:
        hermes_session_id = stable_hermes_session(self.config.role, linear_session_id)
        instructions = (
            f"This is Linear Agent Session {linear_session_id}. Linear is the authoritative task system. "
            f"The named human owner for this session is {owner or 'not provided'}. "
            "Follow the workspace AGENTS.md policy, keep the human owner in control, and link any "
            "Forgejo pull request in the final response."
        )
        path = "/v1/runs"
        body = {"input": text, "instructions": instructions, "session_id": hermes_session_id}
        status, result = self.hermes(path, method="POST", body=body)
        if status != 202 or not result.get("run_id"):
            raise RetryableError(f"Hermes did not start the run: {result}")
        run_id = str(result["run_id"])
        self.update_session(
            linear_session_id,
            hermesSessionId=hermes_session_id,
            activeRunId=run_id,
            approvalRequestedAt=None,
        )
        thread = threading.Thread(
            target=self.consume_run,
            args=(linear_session_id, run_id),
            name=f"linear-run-{run_id[-8:]}",
            daemon=True,
        )
        thread.start()
        return run_id

    def consume_run(self, linear_session_id: str, run_id: str) -> None:
        try:
            with self._open_run_events(run_id) as response:
                for event in parse_sse(iter(response.readline, b"")):
                    self.handle_run_event(linear_session_id, run_id, event)
        except Exception as error:  # keep the polling process alive
            LOG.exception("run event stream failed for %s", run_id)
            try:
                self.activity(linear_session_id, "error", body=f"Hermes event stream failed: {error}")
            except Exception:
                LOG.exception("could not report event stream failure")
        finally:
            with self._lock:
                self._pending_approvals.pop(run_id, None)
            try:
                self.update_session(linear_session_id, activeRunId=None, approvalRequestedAt=None)
            except Exception:
                LOG.exception("could not clear Linear session run state")

    def handle_run_event(self, linear_session_id: str, run_id: str, event: dict[str, Any]) -> None:
        name = str(event.get("event") or "")
        if name == "approval.request":
            command = str(event.get("command") or event.get("description") or "a protected command")
            now = int(time.time())
            with self._lock:
                self._pending_approvals[run_id] = (linear_session_id, float(now))
            self.update_session(linear_session_id, activeRunId=run_id, approvalRequestedAt=now)
            self.activity(
                linear_session_id,
                "elicitation",
                body=(
                    "One-time command approval is required:\n\n"
                    f"`{command}`\n\n"
                    "The configured owner must reply exactly `approve once` or `deny`. "
                    "This request expires after 15 minutes."
                ),
            )
        elif name in {"tool.started", "subagent.started"}:
            tool = str(event.get("tool_name") or event.get("tool") or "Working")
            preview = str(event.get("preview") or event.get("goal") or "")[:1000]
            self.activity(linear_session_id, "action", action=f"Started {tool}", parameter=preview)
        elif name in {"tool.completed", "subagent.completed"}:
            tool = str(event.get("tool_name") or event.get("tool") or "Work")
            result = str(event.get("preview") or event.get("summary") or "Completed")[:1000]
            self.activity(
                linear_session_id,
                "action",
                action=f"Completed {tool}",
                parameter="",
                result=result,
            )
        elif name == "run.completed":
            output = str(event.get("output") or "Completed without a textual response.")
            self.activity(linear_session_id, "response", body=output)
            urls = sorted(set(FORGEJO_PULL_RE.findall(output)))
            if urls:
                self.relay(
                    f"/sessions/{urllib.parse.quote(linear_session_id, safe='')}/external-urls",
                    method="POST",
                    body={
                        "externalUrls": [
                            {"label": f"Forgejo PR {index + 1}", "url": url}
                            for index, url in enumerate(urls[:10])
                        ]
                    },
                )
        elif name in {"run.failed", "run.cancelled"}:
            message = str(event.get("error") or "The Hermes run was cancelled.")
            self.activity(linear_session_id, "error", body=message)

    def handle_prompt(self, event: dict[str, Any], state: dict[str, Any]) -> None:
        linear_session_id = str(event["linearSessionId"])
        payload = event["payload"]
        text = prompt_text(payload)
        normalized = " ".join(text.lower().split())
        run_id = str(state.get("active_run_id") or "")
        approval_at = state.get("approval_requested_at")
        owner = str(event.get("ownerId") or "")
        sender = actor_id(payload)

        if approval_at:
            if not owner or sender != owner:
                self.activity(
                    linear_session_id,
                    "elicitation",
                    body="Only the configured human owner can resolve this command approval.",
                )
                return
            if normalized in APPROVE_ONCE:
                self.hermes(f"/v1/runs/{run_id}/approval", method="POST", body={"choice": "once"})
                self.update_session(linear_session_id, activeRunId=run_id, approvalRequestedAt=None)
                with self._lock:
                    self._pending_approvals.pop(run_id, None)
                self.activity(linear_session_id, "thought", body="One-time approval accepted.")
                return
            if normalized in DENY:
                self.hermes(f"/v1/runs/{run_id}/approval", method="POST", body={"choice": "deny"})
                self.update_session(linear_session_id, activeRunId=run_id, approvalRequestedAt=None)
                with self._lock:
                    self._pending_approvals.pop(run_id, None)
                self.activity(linear_session_id, "thought", body="Command denied.")
                return
            self.activity(
                linear_session_id,
                "elicitation",
                body="An approval is pending. Reply exactly `approve once` or `deny`.",
            )
            return

        if run_id:
            if normalized in STOP:
                self.hermes(f"/v1/runs/{run_id}/stop", method="POST", body={})
                self.activity(linear_session_id, "thought", body="Stopping the active run.")
            else:
                self.hermes(f"/v1/runs/{run_id}/steer", method="POST", body={"input": text})
                self.activity(linear_session_id, "thought", body="Follow-up guidance was added to the run.")
        else:
            self.start_run(linear_session_id, text, human_owner(payload))

    def process(self, event: dict[str, Any]) -> None:
        linear_session_id = str(event.get("linearSessionId") or "")
        if not linear_session_id:
            raise BridgeError("leased event has no Linear session ID")
        action = str(event.get("action") or "created")
        state = self.session_state(linear_session_id)
        if action == "created":
            if not has_human_owner(event["payload"]):
                self.activity(
                    linear_session_id,
                    "elicitation",
                    body=(
                        "This agent session needs a named human creator before work can start. "
                        "Have a human mention or delegate to this agent again."
                    ),
                )
                return
            if state.get("active_run_id"):
                raise RetryableError("this role already has an active run for the session")
            text = prompt_text(event["payload"])
            if not text:
                raise BridgeError("Linear created event did not include promptContext")
            self.start_run(linear_session_id, text, human_owner(event["payload"]))
        elif action == "prompted":
            self.handle_prompt(event, state)
        else:
            LOG.info("ignoring unsupported AgentSessionEvent action %s", action)

    def expire_approvals(self) -> None:
        now = time.time()
        with self._lock:
            expired = [
                (run_id, session_id)
                for run_id, (session_id, requested_at) in self._pending_approvals.items()
                if now - requested_at >= self.config.approval_timeout_seconds
            ]
        for run_id, session_id in expired:
            try:
                self.hermes(f"/v1/runs/{run_id}/approval", method="POST", body={"choice": "deny"})
                self.update_session(session_id, activeRunId=run_id, approvalRequestedAt=None)
                self.activity(session_id, "error", body="Command approval expired and was denied.")
            except Exception:
                LOG.exception("failed to expire approval for %s", run_id)
                continue
            with self._lock:
                self._pending_approvals.pop(run_id, None)

    def run_forever(self) -> None:
        LOG.info("starting outbound Linear bridge for role %s", self.config.role)
        while True:
            self.expire_approvals()
            try:
                status, event = self.relay("/lease", method="POST", body={})
                if status == 204 or not event:
                    time.sleep(self.config.poll_seconds)
                    continue
                delivery_id = str(event.get("deliveryId") or "")
                try:
                    self.process(event)
                except RetryableError as error:
                    LOG.warning("retrying Linear event %s: %s", delivery_id, error)
                    self.acknowledge(delivery_id, retry=True, error=str(error))
                except Exception as error:
                    LOG.exception("Linear event %s failed", delivery_id)
                    try:
                        if event.get("linearSessionId"):
                            self.activity(str(event["linearSessionId"]), "error", body=str(error))
                    finally:
                        self.acknowledge(delivery_id, error=str(error))
                else:
                    self.acknowledge(delivery_id)
            except RetryableError as error:
                LOG.warning("relay unavailable: %s", error)
                time.sleep(min(self.config.poll_seconds * 5, 30))
            except Exception:
                LOG.exception("unexpected bridge loop failure")
                time.sleep(min(self.config.poll_seconds * 5, 30))


def main() -> None:
    logging.basicConfig(
        level=os.environ.get("LINEAR_LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    parser = argparse.ArgumentParser(description="Hyperion Linear agent bridge")
    subcommands = parser.add_subparsers(dest="command")
    handoff = subcommands.add_parser("handoff", help="create and delegate a linked child issue")
    handoff.add_argument("--target", required=True, choices=sorted(ROLES))
    handoff.add_argument("--parent", required=True)
    handoff.add_argument("--title", required=True)
    handoff.add_argument("--description", required=True)
    args = parser.parse_args()
    bridge = Bridge(Config.from_env(require_hermes=args.command != "handoff"))
    if args.command == "handoff":
        if args.target == bridge.config.role:
            raise BridgeError("handoff target must be a different role")
        _, result = bridge.relay(
            "/handoffs",
            method="POST",
            body={
                "targetRole": args.target,
                "parentIssueId": args.parent,
                "title": args.title,
                "description": args.description,
            },
        )
        print(json.dumps(result, separators=(",", ":")))
        return
    bridge.run_forever()


if __name__ == "__main__":
    main()
