-- MelonThump 2.0 FIX12: Vision watermelon annotation. The iOS client
-- classifies a sample's photos on-device (Apple Vision, `watermelon`
-- label confidence 0-1) and sends the scores as optional meta fields.
-- Advisory only. Additive and nullable (older clients send nothing),
-- portable across PostgreSQL and H2 (PG mode), like V4-V7.
ALTER TABLE samples ADD COLUMN vision_watermelon DOUBLE PRECISION;
ALTER TABLE samples ADD COLUMN vision_cutopen_watermelon DOUBLE PRECISION;
