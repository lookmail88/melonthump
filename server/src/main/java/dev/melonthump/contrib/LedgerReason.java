package dev.melonthump.contrib;

/** Why an ad-free ledger row exists (design doc 2.0 §7 item 9). */
public enum LedgerReason {
    SAMPLE_APPROVED,
    VOID_CLAWBACK,
    ADMIN_GRANT,
    ADMIN_REVOKE
}
