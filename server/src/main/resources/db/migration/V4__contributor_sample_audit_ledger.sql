-- MelonThump 2.0: contributor data layer, audit log, ad-free ledger
-- (design doc 2.0 §2 items 6-8, §5 item 6, §7 items 8-11). Additive
-- only: four new tables, nothing existing is altered.
--
-- Portability: this file runs unchanged on PostgreSQL (production) and
-- on H2 in PostgreSQL compatibility mode (tests and the qa profile), so
-- it deliberately avoids PG-only types (jsonb, arrays, generated
-- columns). Enum-like columns are VARCHAR + CHECK; JSON payloads are
-- TEXT holding a JSON document.

-- One row per contributor application. contributor_id is the anonymous
-- UUID the client generates at opt-in and keeps in the Keychain.
CREATE TABLE contributors (
    contributor_id  UUID         PRIMARY KEY,
    note            TEXT         NOT NULL,   -- enrollment note; owner-only, never modeling data
    status          VARCHAR(16)  NOT NULL,
    created_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT ck_contributors_status CHECK (status IN ('PENDING', 'APPROVED', 'DECLINED', 'REVOKED'))
);
CREATE INDEX idx_contributors_status ON contributors (status, created_at);

-- One row per contributed sample: the server mirror of one melon record
-- (§2 item 8). Removal is void-marking (status VOIDED), never DELETE.
CREATE TABLE samples (
    id                BIGSERIAL    PRIMARY KEY,
    contributor_id    UUID         NOT NULL REFERENCES contributors (contributor_id),
    variety           VARCHAR(16)  NOT NULL,
    weight_grams      INTEGER,
    weight_provenance VARCHAR(16),
    source            VARCHAR(64),
    melon_date        DATE,
    has_appearance    BOOLEAN      NOT NULL DEFAULT FALSE,
    has_recording     BOOLEAN      NOT NULL DEFAULT FALSE,
    has_cut_open      BOOLEAN      NOT NULL DEFAULT FALSE,
    has_feedback      BOOLEAN      NOT NULL DEFAULT FALSE,
    complete          BOOLEAN      NOT NULL DEFAULT FALSE,  -- derived: all four parts present
    score             INTEGER,
    taste_tags        TEXT,                                 -- JSON array of preset tag strings
    band_truth        VARCHAR(16),
    status            VARCHAR(16)  NOT NULL,
    return_reason     TEXT,
    created_at        TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at        TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT ck_samples_variety CHECK (variety IN
        ('SEEDLESS', 'SEEDED', 'MINI', 'YELLOW_FLESH', 'KIRIN', 'BLACK_BEAUTY', 'OTHER')),
    CONSTRAINT ck_samples_weight CHECK (weight_grams IS NULL OR weight_grams > 0),
    CONSTRAINT ck_samples_weight_provenance CHECK (weight_provenance IS NULL OR weight_provenance IN
        ('PHOTO_ESTIMATED', 'MANUAL_ESTIMATE', 'SCALE_MEASURED')),
    CONSTRAINT ck_samples_complete CHECK (complete =
        (has_appearance AND has_recording AND has_cut_open AND has_feedback)),
    CONSTRAINT ck_samples_score CHECK (score IS NULL OR (score >= 0 AND score <= 100)),
    CONSTRAINT ck_samples_band_truth CHECK (band_truth IS NULL OR band_truth IN
        ('UNRIPE', 'RIPE', 'OVERRIPE')),
    CONSTRAINT ck_samples_status CHECK (status IN ('SUBMITTED', 'APPROVED', 'RETURNED', 'VOIDED'))
);
CREATE INDEX idx_samples_contributor ON samples (contributor_id, created_at);
CREATE INDEX idx_samples_status ON samples (status, created_at);

-- Minimal append-only audit log (§7 item 11). The application has no
-- UPDATE or DELETE path for this table.
CREATE TABLE audit_log (
    id           BIGSERIAL    PRIMARY KEY,
    actor        VARCHAR(128) NOT NULL,
    action       VARCHAR(64)  NOT NULL,
    object_type  VARCHAR(32)  NOT NULL,
    object_id    VARCHAR(64)  NOT NULL,
    before_json  TEXT,
    after_json   TEXT,
    created_at   TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_log_object ON audit_log (object_type, object_id, id);
CREATE INDEX idx_audit_log_created ON audit_log (created_at);

-- Ad-free allowance ledger (§7 item 9). Balance = SUM(delta) per
-- contributor. Separate book from the Invite credit economy.
CREATE TABLE ad_free_ledger (
    id              BIGSERIAL    PRIMARY KEY,
    contributor_id  UUID         NOT NULL REFERENCES contributors (contributor_id),
    delta           INTEGER      NOT NULL,
    reason          VARCHAR(32)  NOT NULL,
    reference_id    VARCHAR(64),
    created_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);
CREATE INDEX idx_ad_free_ledger_contributor ON ad_free_ledger (contributor_id, id);
