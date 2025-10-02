CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS btree_gin;

CREATE TABLE users (
  id       BIGSERIAL PRIMARY KEY,
  email    TEXT NOT NULL UNIQUE,
  name     TEXT,
  status   TEXT NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE auth_tokens (
  id                 BIGSERIAL PRIMARY KEY,
  user_id            BIGINT REFERENCES users(id) ON DELETE SET NULL,
  token_hash         TEXT NOT NULL UNIQUE,
  scopes             TEXT[] NOT NULL DEFAULT '{}',
  issued_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at         TIMESTAMPTZ,
  revoked            BOOLEAN NOT NULL DEFAULT FALSE,
  last_used_at       TIMESTAMPTZ,
  rate_limit_per_min INTEGER NOT NULL DEFAULT 60 CHECK (rate_limit_per_min > 0)
);


CREATE TABLE faq_cache (
  id               BIGSERIAL PRIMARY KEY,
  canonical_key    TEXT NOT NULL,   -- normalized stable hash
  query_text       TEXT NOT NULL,   -- original normalized query
  intent           TEXT NOT NULL,
  provider         TEXT,
  response_json    JSONB NOT NULL,             -- Provider payload
  message          TEXT,                       -- human-friendly summary
  ttl_seconds      INTEGER NOT NULL DEFAULT 1800 CHECK (ttl_seconds > 0),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_accessed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(canonical_key, intent, provider)
);

CREATE TABLE model_artifacts (
  id          BIGSERIAL PRIMARY KEY,
  name        TEXT NOT NULL,                 -- e.g., 'intent_lr_tfidf'
  version     TEXT NOT NULL,                 -- e.g., '2025-09-30_01'
  sha256      TEXT,                          -- Makes sure were loading the model we stored
  uri         TEXT NOT NULL,                 -- Stores the path to the model
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  is_active   BOOLEAN NOT NULL DEFAULT FALSE
);


CREATE TABLE request_log (
  id            BIGSERIAL PRIMARY KEY,
  model_id      BIGINT REFERENCES model_artifacts(id) ON DELETE SET NULL,
  received_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  token_id      BIGINT REFERENCES auth_tokens(id) ON DELETE SET NULL,
  user_id       BIGINT REFERENCES users(id) ON DELETE SET NULL,
  source_ip     INET,
  query_len     INTEGER CHECK (query_len >= 0),
  intent        TEXT,
  provider      TEXT,
  status_code   INTEGER,
  latency_ms    INTEGER CHECK (latency_ms IS NULL OR latency_ms >= 0),
  cache_hit     BOOLEAN,
  error_text    TEXT
);



-------------------------------------- ----------VIEWS -----------------------------------------

-- Active tokens
CREATE OR REPLACE VIEW v_active_tokens AS
SELECT id, user_id, scopes, issued_at, expires_at, last_used_at, rate_limit_per_min
FROM auth_tokens
WHERE revoked = FALSE AND (expires_at IS NULL OR expires_at > now());

-- FAQ entries currently valid by TTL (effective cache)
CREATE OR REPLACE VIEW v_faq_valid AS
SELECT *
FROM faq_cache
WHERE (created_at + make_interval(secs => ttl_seconds)) > now();


---------------------------------------Indexes for faster lookup----------------------------------

CREATE INDEX auth_tokens_user_idx   ON auth_tokens (user_id);
CREATE INDEX auth_tokens_valid_idx  ON auth_tokens (revoked, expires_at);

CREATE INDEX faq_cache_key_idx   ON faq_cache (canonical_key);
CREATE INDEX faq_cache_trgm_idx  ON faq_cache USING gin (query_text gin_trgm_ops);
CREATE INDEX faq_cache_intent_idx   ON faq_cache (intent);
CREATE INDEX faq_cache_provider_idx ON faq_cache (provider);

-- Indices for common dashboards
CREATE INDEX request_log_time_idx      ON request_log (received_at DESC);
CREATE INDEX request_log_token_idx     ON request_log (token_id, received_at DESC);
CREATE INDEX request_log_intent_idx    ON request_log (intent, received_at DESC);
CREATE INDEX request_log_provider_idx  ON request_log (provider, received_at DESC);
CREATE INDEX request_log_status_idx    ON request_log (status_code, received_at DESC);