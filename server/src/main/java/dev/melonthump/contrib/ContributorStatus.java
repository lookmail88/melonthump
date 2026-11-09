package dev.melonthump.contrib;

/** Contributor application / standing (design doc 2.0 §5 item 6). */
public enum ContributorStatus {
    /** Application submitted, awaiting the owner's decision. */
    PENDING,
    /** Owner approved: sample submission rights are active. */
    APPROVED,
    /** Owner declined the application. */
    DECLINED,
    /** A previous approval was switched off by the owner. */
    REVOKED
}
