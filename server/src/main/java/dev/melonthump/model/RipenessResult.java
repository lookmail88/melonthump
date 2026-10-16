package dev.melonthump.model;

/**
 * Classification result from a {@link RipenessModel}.
 *
 * @param verdict    the ripeness verdict
 * @param confidence confidence in [0, 1]
 */
public record RipenessResult(RipenessVerdict verdict, double confidence) {
    public RipenessResult {
        if (confidence < 0 || confidence > 1) {
            throw new IllegalArgumentException("confidence must be in [0, 1]");
        }
    }
}
