package dev.melonthump.api;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import dev.melonthump.contrib.AdminOverviewService;
import dev.melonthump.contrib.AdminSettingsService;
import dev.melonthump.contrib.AdminSettingsService.SettingView;
import dev.melonthump.contrib.SettingKey;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import java.util.List;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * S4 admin page support (design doc 2.0 §7 items 9 + 11): the
 * runtime-editable operational ad switches (page C) and the read-only
 * overview (page D). Same kill-switch and Access-identity audit actor as
 * {@link AdminController}.
 *
 * <p>Only the four {@link SettingKey}s are editable. The release-class
 * numbers (latestVersion, minSupportedVersion) are not settings and have
 * no write path here or anywhere else in the admin API.
 */
@RestController
@RequestMapping("/api/admin")
@ConditionalOnProperty(name = "melonthump.admin.enabled", havingValue = "true")
@Tag(name = "admin", description = "Owner console API (behind Cloudflare Access in production)")
public class AdminConsoleController {

    private final AdminSettingsService settings;
    private final AdminOverviewService overview;
    private final ObjectMapper objectMapper;

    public AdminConsoleController(AdminSettingsService settings, AdminOverviewService overview,
                                  ObjectMapper objectMapper) {
        this.settings = settings;
        this.overview = overview;
        this.objectMapper = objectMapper;
    }

    @Operation(summary = "Every runtime setting with its effective value, default and override flag",
            description = "Keys: adfree_per_approved_sample, promo_ends_at_epoch_millis, initial_free_thumps, "
                    + "credit_per_ad. value / defaultValue are strings; null means unset "
                    + "(promo_ends_at_epoch_millis: no promo running).")
    @GetMapping("/settings")
    public List<SettingView> settings() {
        return settings.list();
    }

    @Operation(summary = "Override one setting",
            description = "Body {\"key\": \"...\", \"value\": \"...\"} (value may also be a JSON integer). "
                    + "adfree_per_approved_sample / initial_free_thumps: integer >= 0; "
                    + "promo_ends_at_epoch_millis: integer >= 0 (epoch ms); credit_per_ad: -1 (free day) or "
                    + "integer >= 0. Unknown key or invalid value: 400. Writes an audit row SETTING_CHANGED.")
    @PutMapping("/settings")
    public SettingView put(@RequestBody(required = false) byte[] body) {
        JsonNode json = AdminParams.object(objectMapper, body);
        SettingKey key = key(AdminParams.requiredText(json, "key", 64));
        JsonNode v = json.get("value");
        String raw;
        if (v != null && v.isTextual()) {
            raw = v.asText();
        } else if (v != null && v.isIntegralNumber()) {
            raw = v.bigIntegerValue().toString();
        } else {
            throw AdminParams.bad("value is required (a string or an integer)");
        }
        try {
            return settings.set(key, raw, AdminActor.current());
        } catch (SettingKey.InvalidSettingException e) {
            throw AdminParams.bad(e.getMessage());
        }
    }

    @Operation(summary = "Remove a setting's override (back to the default)",
            description = "Unknown key: 400. No override present: 404. Writes an audit row SETTING_RESET.")
    @DeleteMapping("/settings/{key}")
    public SettingView reset(@PathVariable String key) {
        return settings.reset(key(key), AdminActor.current());
    }

    @Operation(summary = "Read-only overview counts (admin page D)",
            description = "contributors / samples: counts per status. completeSamplesApproved: APPROVED samples "
                    + "with all four parts (the count toward the 30-sample modeling threshold). pendingReview: "
                    + "SUBMITTED samples. adFreeOutstanding: sum of all contributors' current ad-free balances.")
    @GetMapping("/overview")
    public AdminOverviewService.Overview overview() {
        return overview.overview();
    }

    private static SettingKey key(String raw) {
        return SettingKey.of(raw).orElseThrow(() -> AdminParams.bad("unknown setting key: " + raw.strip()
                + " (known: adfree_per_approved_sample, promo_ends_at_epoch_millis, initial_free_thumps, "
                + "credit_per_ad)"));
    }
}
