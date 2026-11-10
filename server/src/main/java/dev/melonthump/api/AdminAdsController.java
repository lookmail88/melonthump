package dev.melonthump.api;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import dev.melonthump.contrib.AdExemption;
import dev.melonthump.contrib.AdExemptionService;
import dev.melonthump.contrib.AdFreeLedgerEntry;
import dev.melonthump.contrib.Contributor;
import dev.melonthump.contrib.IncentiveService;
import dev.melonthump.dto.ContributionDtos.AdExemptionView;
import dev.melonthump.dto.ContributionDtos.AdFreeGrantResponse;
import dev.melonthump.dto.ContributionDtos.AdFreeLedgerResponse;
import dev.melonthump.dto.ContributionDtos.ContributorExemptionView;
import dev.melonthump.dto.ContributionDtos.LedgerEntryView;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import java.util.List;
import java.util.UUID;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Owner ad management (design doc 2.0 §2 items 6-7, §7 items 9 + 11,
 * admin page C): contributor ad-free ledger and manual grants, permanent
 * contributor exemption, and the install-id adExempt allowlist. Same
 * kill-switch and audit actor as {@link AdminController}.
 */
@RestController
@RequestMapping("/api/admin")
@ConditionalOnProperty(name = "melonthump.admin.enabled", havingValue = "true")
@Tag(name = "admin", description = "Owner console API (behind Cloudflare Access in production)")
public class AdminAdsController {

    private final IncentiveService incentives;
    private final AdExemptionService exemptions;
    private final ObjectMapper objectMapper;

    public AdminAdsController(IncentiveService incentives, AdExemptionService exemptions, ObjectMapper objectMapper) {
        this.incentives = incentives;
        this.exemptions = exemptions;
        this.objectMapper = objectMapper;
    }

    // ---- contributor ad-free ledger ----------------------------------------------

    @Operation(summary = "Manual ad-free grant (positive delta) or revocation (negative delta)",
            description = "Body {\"delta\": non-zero integer, \"reason\": required, at most 64 chars}. A negative "
                    + "delta stops at a zero balance; the response reports what was applied. The ledger row "
                    + "carries reason ADMIN_GRANT; the free-text reason is kept in the audit row.")
    @PostMapping("/contributors/{contributorId}/adfree/grants")
    public AdFreeGrantResponse grant(@PathVariable String contributorId,
                                     @RequestBody(required = false) byte[] body) {
        UUID id = AdminParams.uuid(contributorId, "contributorId");
        JsonNode json = AdminParams.object(objectMapper, body);
        JsonNode d = json.get("delta");
        if (d == null || !d.isIntegralNumber() || !d.canConvertToInt()) {
            throw AdminParams.bad("delta must be an integer");
        }
        int delta = d.intValue();
        if (delta == 0) {
            throw AdminParams.bad("delta must be non-zero");
        }
        if (Math.abs((long) delta) > IncentiveService.MAX_GRANT_MAGNITUDE) {
            throw AdminParams.bad("delta magnitude must be at most " + IncentiveService.MAX_GRANT_MAGNITUDE);
        }
        String reason = AdminParams.requiredText(json, "reason", IncentiveService.MAX_GRANT_REASON_LENGTH);
        IncentiveService.GrantResult r = incentives.grant(id, delta, reason, AdminActor.current());
        return new AdFreeGrantResponse(r.contributorId(), r.requestedDelta(), r.appliedDelta(), r.balance());
    }

    @Operation(summary = "A contributor's ad-free balance and ledger, newest first")
    @GetMapping("/contributors/{contributorId}/adfree")
    public AdFreeLedgerResponse ledger(@PathVariable String contributorId) {
        IncentiveService.LedgerView v = incentives.ledger(AdminParams.uuid(contributorId, "contributorId"));
        List<LedgerEntryView> entries = v.entries().stream().map(AdminAdsController::entry).toList();
        return new AdFreeLedgerResponse(v.contributor().getContributorId(), v.balance(), entries,
                v.contributor().isAdExemptPermanent());
    }

    @Operation(summary = "Set or clear a contributor's permanent ad exemption",
            description = "Body {\"permanent\": true|false}. Setting the current value is a 200 no-op.")
    @PostMapping("/contributors/{contributorId}/exemption")
    public ContributorExemptionView exemption(@PathVariable String contributorId,
                                              @RequestBody(required = false) byte[] body) {
        UUID id = AdminParams.uuid(contributorId, "contributorId");
        JsonNode p = AdminParams.object(objectMapper, body).get("permanent");
        if (p == null || !p.isBoolean()) {
            throw AdminParams.bad("permanent must be true or false");
        }
        Contributor c = incentives.setPermanentExemption(id, p.booleanValue(), AdminActor.current());
        return new ContributorExemptionView(c.getContributorId(), c.getStatus().name(), c.isAdExemptPermanent());
    }

    // ---- install-id allowlist (adExempt) ---------------------------------------------

    @Operation(summary = "List the install-id ad-exemption allowlist, newest first")
    @GetMapping("/exemptions")
    public List<AdExemptionView> exemptions() {
        return exemptions.list().stream().map(AdminAdsController::view).toList();
    }

    @Operation(summary = "Add an install to the ad-exemption allowlist, or update its note",
            description = "Body {\"installId\": required, at most 64 chars, \"note\": optional, at most 128 chars}. "
                    + "A UUID install id is stored in canonical lower case. 201 on create, 200 on update.")
    @PostMapping("/exemptions")
    public ResponseEntity<AdExemptionView> setExemption(@RequestBody(required = false) byte[] body) {
        JsonNode json = AdminParams.object(objectMapper, body);
        String installId = AdExemptionService.normalize(
                AdminParams.requiredText(json, "installId", AdExemptionService.MAX_INSTALL_ID_LENGTH));
        String note = null;
        JsonNode n = json.get("note");
        if (n != null && !n.isNull()) {
            if (!n.isTextual()) {
                throw AdminParams.bad("note must be a string");
            }
            note = n.asText().strip();
            if (note.isEmpty()) {
                note = null;
            } else if (note.length() > AdExemptionService.MAX_NOTE_LENGTH) {
                throw AdminParams.bad("note must be at most " + AdExemptionService.MAX_NOTE_LENGTH + " characters");
            }
        }
        AdExemptionService.SetResult r = exemptions.set(installId, note, AdminActor.current());
        return ResponseEntity.status(r.created() ? HttpStatus.CREATED : HttpStatus.OK).body(view(r.exemption()));
    }

    @Operation(summary = "Remove an install from the ad-exemption allowlist (404 when absent)")
    @DeleteMapping("/exemptions/{installId}")
    public ResponseEntity<Void> removeExemption(@PathVariable String installId) {
        String id = AdExemptionService.normalize(installId);
        if (id == null || id.length() > AdExemptionService.MAX_INSTALL_ID_LENGTH) {
            throw AdminParams.bad("installId must be 1-" + AdExemptionService.MAX_INSTALL_ID_LENGTH + " characters");
        }
        exemptions.remove(id, AdminActor.current());
        return ResponseEntity.noContent().build();
    }

    private static LedgerEntryView entry(AdFreeLedgerEntry e) {
        return new LedgerEntryView(e.getId(), e.getDelta(), e.getReason().name(), e.getReferenceId(),
                e.getCreatedAt().toString());
    }

    private static AdExemptionView view(AdExemption e) {
        return new AdExemptionView(e.getInstallId(), e.getNote(), e.getCreatedAt().toString());
    }
}
