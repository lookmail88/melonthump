-- MelonThump 2.0 S2: contributed material files (design doc 2.0 §5
-- items 1 + 6, §7 item 8). Additive only: one new table, nothing
-- existing is altered. Portable across PostgreSQL and H2 (PG mode),
-- like V4.
--
-- One row per stored file. The bytes live on server-local disk under
-- melonthump.contrib.storage-dir at stored_path (relative to that root,
-- layout <contributorId>/<sampleId>/<part>-<n>.<ext>). Rows are removed
-- together with the files when a contributor withdraws a sample (§7
-- item 8 true deletion); the audit_log row is the surviving record.
CREATE TABLE sample_files (
    id            BIGSERIAL     PRIMARY KEY,
    sample_id     BIGINT        NOT NULL REFERENCES samples (id),
    part          VARCHAR(16)   NOT NULL,
    sha256        VARCHAR(64)   NOT NULL,   -- lowercase hex
    size_bytes    BIGINT        NOT NULL,
    content_type  VARCHAR(100)  NOT NULL,
    stored_path   VARCHAR(512)  NOT NULL,
    created_at    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT ck_sample_files_part CHECK (part IN ('APPEARANCE', 'RECORDING', 'CUT_OPEN')),
    CONSTRAINT ck_sample_files_size CHECK (size_bytes > 0),
    CONSTRAINT uq_sample_files_path UNIQUE (stored_path)
);
CREATE INDEX idx_sample_files_sample ON sample_files (sample_id, id);
