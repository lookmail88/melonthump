-- MelonThump 1.1.0: usage events + App Attest state (design doc §4).
-- app_event carries two additive columns beyond the doc's DDL:
--   event_id  — client-generated per-event UUID; makes batch upload
--               idempotent (a retried flush must not double-count).
--   session_id — per-launch UUID, used to group one app session.
CREATE TABLE app_event (
    id            BIGSERIAL PRIMARY KEY,
    event_id      UUID        NOT NULL,
    install_id    UUID        NOT NULL,
    session_id    UUID,
    type          VARCHAR(32) NOT NULL,
    verdict       VARCHAR(16),
    slot          VARCHAR(32),
    unit_source   VARCHAR(16),
    error_code    INTEGER,
    client_ts     TIMESTAMP WITH TIME ZONE NOT NULL,
    received_ts   TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX idx_app_event_event_id ON app_event (event_id);
CREATE INDEX idx_app_event_received ON app_event (received_ts);
CREATE INDEX idx_app_event_type_received ON app_event (type, received_ts);

CREATE TABLE attest_key (
    key_id        VARCHAR(64) PRIMARY KEY,   -- App Attest key identifier
    install_id    UUID NOT NULL,
    public_key    BYTEA NOT NULL,            -- verified at enrollment (X.509 SPKI)
    sign_count    BIGINT NOT NULL DEFAULT 0, -- anti-replay counter
    environment   VARCHAR(16) NOT NULL,      -- production / develop
    created_at    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

CREATE TABLE attest_challenge (
    challenge     BYTEA PRIMARY KEY,
    expires_at    TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);
