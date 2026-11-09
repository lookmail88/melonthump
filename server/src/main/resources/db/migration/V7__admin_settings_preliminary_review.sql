-- MelonThump 2.0 S4: runtime-editable admin settings and Pepper's
-- preliminary-review fields (design doc 2.0 §7 items 9-11). Additive,
-- portable across PostgreSQL and H2 (PG mode), like V4-V6.

-- 1. Runtime settings overrides. A row overrides the properties / env
--    default of one known key; deleting the row reverts to the default.
--    Only the operational ad switches live here (§7 item 11 boundary):
--    adfree_per_approved_sample, promo_ends_at_epoch_millis,
--    initial_free_thumps, credit_per_ad. Release-class numbers
--    (latestVersion, minSupportedVersion) are never stored here.
--    "key" / "value" are quoted: both are keywords in H2 (unquoted they
--    are non-reserved in PostgreSQL; the quoted lower-case names are the
--    same identifiers there).
CREATE TABLE admin_settings (
    "key"       VARCHAR(64)   PRIMARY KEY,
    "value"     VARCHAR(256)  NOT NULL,
    updated_at  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_by  VARCHAR(128)
);

-- 2. Pepper's preliminary review (§7 item 10): an advisory
--    recommendation per sample; the owner alone makes the final call.
ALTER TABLE samples ADD COLUMN pepper_recommendation VARCHAR(16);
ALTER TABLE samples ADD COLUMN pepper_note TEXT;
ALTER TABLE samples ADD COLUMN pepper_reviewed_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE samples ADD CONSTRAINT ck_samples_pepper_recommendation CHECK (pepper_recommendation IS NULL
    OR pepper_recommendation IN ('SUGGEST_APPROVE', 'SUGGEST_RETURN', 'FLAG_OWNER'));
