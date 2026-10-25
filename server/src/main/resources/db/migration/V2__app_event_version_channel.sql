-- 1.1.0 follow-up: client-reported app version + distribution channel
-- on the usage ledger. Channel is computed on-device from the App Store
-- receipt (xcode / testflight / appstore) and is analytics-grade only,
-- never a trust input. Both columns nullable: earlier 1.1.0 clients
-- omit them and their rows simply aggregate under "unknown".
ALTER TABLE app_event ADD COLUMN app_version VARCHAR(32);
ALTER TABLE app_event ADD COLUMN channel VARCHAR(16);
