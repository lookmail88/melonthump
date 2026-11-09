-- MelonThump 2.0 FIX12B: per-kind Vision annotation. The iOS client now
-- judges each photo against its own kind and sends one score per kind:
-- the best whole-melon photo and the best rind close-up (the cut-open
-- score keeps V8's vision_cutopen_watermelon). V8's combined
-- vision_watermelon stays for FIX12 clients. Advisory only. Additive and
-- nullable, portable across PostgreSQL and H2 (PG mode), like V4-V8.
ALTER TABLE samples ADD COLUMN vision_whole_watermelon DOUBLE PRECISION;
ALTER TABLE samples ADD COLUMN vision_rind_watermelon DOUBLE PRECISION;
