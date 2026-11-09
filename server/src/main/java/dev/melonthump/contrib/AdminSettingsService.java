package dev.melonthump.contrib;

import java.util.ArrayList;
import java.util.EnumMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * Runtime-editable admin settings (design doc 2.0 §7 items 9 + 11, S4).
 * Each {@link SettingKey} has a default from properties / env (exactly the
 * values the server used before S4) and an optional override row in
 * {@code admin_settings}; the effective value is the override when present,
 * else the default.
 *
 * <p>Consumers (the version policy and the incentive ledger) read the
 * effective values through a small in-memory snapshot that is refreshed
 * at most every {@code melonthump.admin.settings-cache-millis} (default
 * 5 s) and dropped immediately after a local write, so a change made on
 * one replica reaches every replica within that window. Reading the
 * overrides can never break a consumer: a failed read, or a stored value
 * that no longer validates, falls back to the default.
 */
@Service
public class AdminSettingsService {

    private static final Logger log = LoggerFactory.getLogger(AdminSettingsService.class);

    public static final String OBJECT_SETTING = "SETTING";
    public static final String ACTION_CHANGED = "SETTING_CHANGED";
    public static final String ACTION_RESET = "SETTING_RESET";

    /** Design value of the per-version first-N allowance (1.2.0 §3); fallback for invalid config. */
    public static final int DEFAULT_INITIAL_FREE_THUMPS = 2;

    private final AdminSettingRepository repository;
    private final AuditLogService audit;
    private final TransactionTemplate tx;
    private final TransactionTemplate readTx;
    private final Map<SettingKey, String> defaults = new EnumMap<>(SettingKey.class);
    private final long cacheNanos;

    private volatile Snapshot cached;

    /** One effective setting as the admin page sees it. {@code value} / {@code defaultValue} may be null. */
    public record SettingView(String key, String value, String defaultValue, boolean overridden) {
    }

    /** The effective values the consumers use. {@code promoEndsAtEpochMillis} null = no promo. */
    public record Effective(int adfreePerApprovedSample, Long promoEndsAtEpochMillis, int initialFreeThumps,
                            int creditPerAd) {
    }

    private record Snapshot(Effective values, long loadedAtNanos) {
    }

    public static final class SettingNotOverriddenException extends RuntimeException {
        public SettingNotOverriddenException(String key) {
            super("setting " + key + " has no override");
        }
    }

    public AdminSettingsService(AdminSettingRepository repository, AuditLogService audit,
                                PlatformTransactionManager transactionManager,
                                @Value("${melonthump.contrib.adfree-per-approved-sample:5}") int adfreePerApprovedSample,
                                @Value("${melonthump.client.promo-ends-at-epoch-millis:}") String promoEndsAtRaw,
                                @Value("${melonthump.client.initial-free-thumps:2}") String initialFreeThumpsRaw,
                                @Value("${melonthump.client.credit-per-ad:1}") int creditPerAd,
                                @Value("${melonthump.admin.settings-cache-millis:5000}") long cacheMillis) {
        if (adfreePerApprovedSample < 0) {
            throw new IllegalArgumentException("melonthump.contrib.adfree-per-approved-sample must be >= 0");
        }
        this.repository = repository;
        this.audit = audit;
        this.tx = new TransactionTemplate(transactionManager);
        this.readTx = new TransactionTemplate(transactionManager);
        this.readTx.setReadOnly(true);
        this.cacheNanos = Math.max(0, cacheMillis) * 1_000_000L;
        defaults.put(SettingKey.ADFREE_PER_APPROVED_SAMPLE, Integer.toString(adfreePerApprovedSample));
        Long promo = parseEpochMillis(promoEndsAtRaw);
        defaults.put(SettingKey.PROMO_ENDS_AT_EPOCH_MILLIS, promo == null ? null : promo.toString());
        defaults.put(SettingKey.INITIAL_FREE_THUMPS,
                Integer.toString(parseInt(initialFreeThumpsRaw, 0, DEFAULT_INITIAL_FREE_THUMPS)));
        defaults.put(SettingKey.CREDIT_PER_AD, Integer.toString(creditPerAd));
    }

    // ---- consumers -------------------------------------------------------------

    /** Effective values for the policy / ledger; never throws. */
    public Effective effective() {
        Snapshot s = cached;
        long now = System.nanoTime();
        if (s != null && now - s.loadedAtNanos() < cacheNanos) {
            return s.values();
        }
        Effective e = toEffective(loadOverridesSafely());
        cached = new Snapshot(e, now);
        return e;
    }

    public int adfreePerApprovedSample() {
        return effective().adfreePerApprovedSample();
    }

    // ---- admin -----------------------------------------------------------------

    /** Every known key, in {@link SettingKey} order, read fresh from the database. */
    public List<SettingView> list() {
        Map<SettingKey, String> overrides = readTx.execute(status -> overrides(repository.findAll()));
        List<SettingView> out = new ArrayList<>();
        for (SettingKey k : SettingKey.values()) {
            out.add(view(k, overrides));
        }
        return out;
    }

    /**
     * Writes (or replaces) the override of {@code key}. {@code rawValue} is
     * validated with {@link SettingKey#canonicalize}. Always writes the row
     * and an audit row, even when the value is unchanged.
     */
    public SettingView set(SettingKey key, String rawValue, String actor) {
        String value = key.canonicalize(rawValue);
        SettingView v;
        try {
            v = tx.execute(status -> setInTx(key, value, actor));
        } catch (DataIntegrityViolationException race) {
            // A concurrent create of the same key won: apply as an update.
            v = tx.execute(status -> setInTx(key, value, actor));
        }
        cached = null;
        return v;
    }

    /** Removes the override of {@code key} (back to the default); none present → {@link SettingNotOverriddenException}. */
    public SettingView reset(SettingKey key, String actor) {
        SettingView v = tx.execute(status -> {
            AdminSetting row = repository.findForUpdate(key.key())
                    .orElseThrow(() -> new SettingNotOverriddenException(key.key()));
            Map<String, Object> before = snapshot(key, row.getValue(), true);
            repository.delete(row);
            repository.flush();
            String def = defaults.get(key);
            audit.record(actor, ACTION_RESET, OBJECT_SETTING, key.key(), before, snapshot(key, def, false));
            return new SettingView(key.key(), def, def, false);
        });
        cached = null;
        return v;
    }

    private SettingView setInTx(SettingKey key, String value, String actor) {
        var existing = repository.findForUpdate(key.key());
        Map<String, Object> before = existing
                .map(r -> snapshot(key, r.getValue(), true))
                .orElseGet(() -> snapshot(key, defaults.get(key), false));
        if (existing.isPresent()) {
            AdminSetting row = existing.get();
            row.update(value, actor);
            repository.saveAndFlush(row);
        } else {
            repository.saveAndFlush(new AdminSetting(key.key(), value, actor));
        }
        audit.record(actor, ACTION_CHANGED, OBJECT_SETTING, key.key(), before, snapshot(key, value, true));
        return new SettingView(key.key(), value, defaults.get(key), true);
    }

    // ---- internals -------------------------------------------------------------

    private Map<SettingKey, String> loadOverridesSafely() {
        try {
            return readTx.execute(status -> overrides(repository.findAll()));
        } catch (RuntimeException e) {
            log.warn("reading admin settings failed; using defaults", e);
            return new EnumMap<>(SettingKey.class);
        }
    }

    /** Valid overrides only; a stored value that no longer validates is ignored (default applies). */
    private static Map<SettingKey, String> overrides(List<AdminSetting> rows) {
        Map<SettingKey, String> m = new EnumMap<>(SettingKey.class);
        for (AdminSetting r : rows) {
            SettingKey.of(r.getKey()).ifPresent(k -> {
                try {
                    m.put(k, k.canonicalize(r.getValue()));
                } catch (SettingKey.InvalidSettingException e) {
                    log.warn("ignoring invalid stored value for setting {}", k.key());
                }
            });
        }
        return m;
    }

    private SettingView view(SettingKey k, Map<SettingKey, String> overrides) {
        boolean overridden = overrides.containsKey(k);
        String def = defaults.get(k);
        return new SettingView(k.key(), overridden ? overrides.get(k) : def, def, overridden);
    }

    private Effective toEffective(Map<SettingKey, String> overrides) {
        String promo = value(SettingKey.PROMO_ENDS_AT_EPOCH_MILLIS, overrides);
        return new Effective(
                Integer.parseInt(value(SettingKey.ADFREE_PER_APPROVED_SAMPLE, overrides)),
                promo == null ? null : Long.valueOf(promo),
                Integer.parseInt(value(SettingKey.INITIAL_FREE_THUMPS, overrides)),
                Integer.parseInt(value(SettingKey.CREDIT_PER_AD, overrides)));
    }

    private String value(SettingKey k, Map<SettingKey, String> overrides) {
        return overrides.containsKey(k) ? overrides.get(k) : defaults.get(k);
    }

    private static Map<String, Object> snapshot(SettingKey key, String value, boolean overridden) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("key", key.key());
        m.put("value", value);
        m.put("overridden", overridden);
        return m;
    }

    /** Malformed or out-of-range config falls back (the pre-S4 VersionController rule). */
    public static int parseInt(String raw, int min, int fallback) {
        if (raw == null || raw.isBlank()) {
            return fallback;
        }
        try {
            int value = Integer.parseInt(raw.trim());
            return value >= min ? value : fallback;
        } catch (NumberFormatException e) {
            return fallback;
        }
    }

    /** Blank or malformed config means "no promo running" (the pre-S4 VersionController rule). */
    static Long parseEpochMillis(String raw) {
        if (raw == null || raw.isBlank()) {
            return null;
        }
        try {
            return Long.parseLong(raw.trim());
        } catch (NumberFormatException e) {
            return null;
        }
    }
}
