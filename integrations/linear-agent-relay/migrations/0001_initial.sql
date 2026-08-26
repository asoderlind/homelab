CREATE TABLE IF NOT EXISTS oauth_states (
  state TEXT PRIMARY KEY,
  role TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS installations (
  role TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL,
  app_user_id TEXT NOT NULL,
  access_token TEXT NOT NULL,
  refresh_token TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS inbox (
  delivery_id TEXT PRIMARY KEY,
  role TEXT NOT NULL,
  linear_session_id TEXT NOT NULL,
  action TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  state TEXT NOT NULL DEFAULT 'queued',
  available_at INTEGER NOT NULL,
  leased_until INTEGER,
  attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  created_at INTEGER NOT NULL,
  completed_at INTEGER
);

CREATE INDEX IF NOT EXISTS inbox_role_queue
  ON inbox(role, state, available_at, created_at);

CREATE TABLE IF NOT EXISTS sessions (
  linear_session_id TEXT PRIMARY KEY,
  role TEXT NOT NULL,
  hermes_session_id TEXT,
  active_run_id TEXT,
  approval_requested_at INTEGER,
  updated_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS sessions_role ON sessions(role, updated_at);
