-- MelonThump 2.0 S3: owner sample review, incentive ledger wiring and the
-- adExempt policy (design doc 2.0 §2 item 6, §7 items 9-11). Additive,
-- portable across PostgreSQL and H2 (PG mode), like V4 / V5.
--
-- 1. Permanent ad exemption granted to a contributor from the admin page
--    (§2 items 6-7). New column with a default: existing rows read FALSE.
ALTER TABLE contributors ADD COLUMN ad_exempt_permanent BOOLEAN NOT NULL DEFAULT FALSE;

-- 2. Owner ad-exemption allowlist by install (§2 item 6). Checked by the
--    version-policy endpoint against the optional X-Install-Id header; the
--    list itself never appears in any client-facing response.
CREATE TABLE ad_exemptions (
    install_id  VARCHAR(64)   PRIMARY KEY,
    note        VARCHAR(128),
    created_at  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- 3. Ledger reasons: ad_free_ledger.reason (V4) carries no CHECK
--    constraint, so the new reason SESSION_UNLOCK needs no schema change.
--    Lookups of the per-sample earning / clawback rows use this index.
CREATE INDEX idx_ad_free_ledger_reference ON ad_free_ledger (reference_id, reason);
