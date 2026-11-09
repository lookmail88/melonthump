package dev.melonthump.contrib;

/** Why an ad-free ledger row exists (design doc 2.0 §7 item 9). */
public enum LedgerReason {
    SAMPLE_APPROVED,
    VOID_CLAWBACK,
    ADMIN_GRANT,
    ADMIN_REVOKE,
    /** A contributor spent one unit to unlock an app session without an ad (S3). */
    SESSION_UNLOCK
}
