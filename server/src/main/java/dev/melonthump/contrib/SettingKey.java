package dev.melonthump.contrib;

import java.util.Optional;

/**
 * The runtime-editable admin settings (design doc 2.0 §7 items 9 + 11):
 * exactly the operational ad switches the admin page may change. The
 * release-class numbers (latestVersion, minSupportedVersion) are
 * deliberately NOT here — they change only through the release process.
 */
public enum SettingKey {

    /** Ad-free units earned per approved complete sample (§7 item 9). Integer ≥ 0. */
    ADFREE_PER_APPROVED_SAMPLE("adfree_per_approved_sample", Kind.NON_NEGATIVE_INT),
    /** End of the launch promo window, epoch millis (policy {@code promoEndsAtEpochMillis}). Long ≥ 0. */
    PROMO_ENDS_AT_EPOCH_MILLIS("promo_ends_at_epoch_millis", Kind.NON_NEGATIVE_LONG),
    /** Per-version first-N allowance (policy {@code initialFreeThumps}, 1.2.0+ only). Integer ≥ 0. */
    INITIAL_FREE_THUMPS("initial_free_thumps", Kind.NON_NEGATIVE_INT),
    /** Credits per rewarded ad (policy {@code creditPerAd}); −1 declares a free day. Integer −1 or ≥ 0. */
    CREDIT_PER_AD("credit_per_ad", Kind.CREDIT_PER_AD);

    private enum Kind { NON_NEGATIVE_INT, NON_NEGATIVE_LONG, CREDIT_PER_AD }

    /** A value that does not satisfy its key's rule. */
    public static final class InvalidSettingException extends RuntimeException {
        public InvalidSettingException(String message) {
            super(message);
        }
    }

    private final String key;
    private final Kind kind;

    SettingKey(String key, Kind kind) {
        this.key = key;
        this.kind = kind;
    }

    public String key() {
        return key;
    }

    public static Optional<SettingKey> of(String key) {
        if (key == null) {
            return Optional.empty();
        }
        for (SettingKey k : values()) {
            if (k.key.equals(key.strip())) {
                return Optional.of(k);
            }
        }
        return Optional.empty();
    }

    /** Validates {@code raw} and returns its canonical string form; throws {@link InvalidSettingException}. */
    public String canonicalize(String raw) {
        String v = raw == null ? "" : raw.strip();
        switch (kind) {
            case NON_NEGATIVE_INT -> {
                int i = parseInt(v, key + " must be an integer >= 0");
                if (i < 0) {
                    throw new InvalidSettingException(key + " must be an integer >= 0");
                }
                return Integer.toString(i);
            }
            case NON_NEGATIVE_LONG -> {
                long l;
                try {
                    l = Long.parseLong(v);
                } catch (NumberFormatException e) {
                    throw new InvalidSettingException(key + " must be an integer >= 0 (epoch milliseconds)");
                }
                if (l < 0) {
                    throw new InvalidSettingException(key + " must be an integer >= 0 (epoch milliseconds)");
                }
                return Long.toString(l);
            }
            case CREDIT_PER_AD -> {
                int i = parseInt(v, key + " must be -1 (free day) or an integer >= 0");
                if (i < -1) {
                    throw new InvalidSettingException(key + " must be -1 (free day) or an integer >= 0");
                }
                return Integer.toString(i);
            }
            default -> throw new IllegalStateException();
        }
    }

    private static int parseInt(String v, String message) {
        try {
            return Integer.parseInt(v);
        } catch (NumberFormatException e) {
            throw new InvalidSettingException(message);
        }
    }
}
