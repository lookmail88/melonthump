package dev.melonthump.contrib;

/** Review state of a contributed sample (design doc 2.0 §7 item 10). */
public enum SampleStatus {
    SUBMITTED,
    APPROVED,
    /** Sent back to the contributor with a reason note; may be fixed and resubmitted. */
    RETURNED,
    /** Removed by void-marking: kept for audit, excluded from modeling and the threshold. */
    VOIDED
}
