-- MelonThump 1.2.0: invite attribution + reward-claim state (design doc
-- 1.2.0 §3). Deliberately minimal — no user profiles (the app has no
-- accounts): an install's invite code, and one attribution row per
-- invitee install. The credit ledger itself stays on-device; the server
-- is the source of truth for confirmation and claim state only.

-- One invite code per inviter install (issued on first request).
CREATE TABLE invite_code (
    install_id    UUID PRIMARY KEY,
    code          VARCHAR(16) NOT NULL,
    created_at    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX idx_invite_code_code ON invite_code (code);

-- One row per invitee. The unique indexes are the double-count guard:
-- an install, and an App Attest key, can be attributed at most once.
CREATE TABLE invite_attribution (
    id                  BIGSERIAL PRIMARY KEY,
    invitee_install_id  UUID        NOT NULL,
    invitee_key_id      VARCHAR(64),             -- null only via the dev simulator bypass
    inviter_install_id  UUID        NOT NULL,
    source              VARCHAR(8)  NOT NULL,    -- link / code
    attributed_at       TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    confirmed_at        TIMESTAMP WITH TIME ZONE, -- invitee's first completed thump analysis
    rewarded            BOOLEAN     NOT NULL DEFAULT FALSE, -- within the inviter's cap
    inviter_claim_id    UUID,                    -- set once the inviter claimed this reward
    invitee_claim_id    UUID                     -- set once the invitee claimed theirs
);
CREATE UNIQUE INDEX idx_invite_attr_invitee ON invite_attribution (invitee_install_id);
CREATE UNIQUE INDEX idx_invite_attr_invitee_key ON invite_attribution (invitee_key_id);
CREATE INDEX idx_invite_attr_inviter ON invite_attribution (inviter_install_id);
