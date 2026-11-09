package dev.melonthump.api;

import dev.melonthump.contrib.AuditLogEntry;
import dev.melonthump.contrib.AuditLogRepository;
import dev.melonthump.contrib.ContributionService;
import dev.melonthump.contrib.Contributor;
import dev.melonthump.contrib.ContributorStatus;
import dev.melonthump.dto.ContributionDtos.AdminApplicationView;
import dev.melonthump.dto.ContributionDtos.AuditEntryView;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.data.domain.Limit;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

/**
 * Owner admin REST surface (design doc 2.0 §2 item 7, §7 item 11),
 * deliberately under its own prefix {@code /api/admin/**}, separate from
 * the client {@code /api/v1}.
 *
 * <p><b>Authentication is NOT done here.</b> In production this prefix
 * sits behind Cloudflare Access (owner email allowlist) at the edge; the
 * server builds no login and stores no password (decided 2026-11-07,
 * §7 item 11). Because the app itself does not authenticate these
 * calls, the controller only exists when {@code melonthump.admin.enabled
 * =true} (env MELONTHUMP_ADMIN_ENABLED, default false): enable it in an
 * environment only once the Access policy covers {@code /api/admin/**}
 * on that host. While disabled, every /api/admin path is a plain 404.
 *
 * <p>Audit actor (S4): the Cloudflare Access identity from the
 * {@code Cf-Access-Authenticated-User-Email} header when present, else
 * {@code owner} — see {@link AdminActor}.
 */
@RestController
@RequestMapping("/api/admin")
@ConditionalOnProperty(name = "melonthump.admin.enabled", havingValue = "true")
@Tag(name = "admin", description = "Owner console API (behind Cloudflare Access in production)")
public class AdminController {

    private final ContributionService service;
    private final AuditLogRepository auditLog;

    public AdminController(ContributionService service, AuditLogRepository auditLog) {
        this.service = service;
        this.auditLog = auditLog;
    }

    @Operation(summary = "List contributor applications, oldest first; optional status filter",
            description = "status = PENDING / APPROVED / DECLINED / REVOKED (case-insensitive); omitted = all.")
    @GetMapping("/applications")
    public List<AdminApplicationView> applications(@RequestParam(required = false) String status) {
        ContributorStatus filter = null;
        if (status != null && !status.isBlank()) {
            try {
                filter = ContributorStatus.valueOf(status.strip().toUpperCase(Locale.ROOT));
            } catch (IllegalArgumentException e) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                        "status must be PENDING / APPROVED / DECLINED / REVOKED");
            }
        }
        return service.listApplications(filter).stream().map(AdminController::view).toList();
    }

    @Operation(summary = "Approve an application (PENDING / DECLINED / REVOKED -> APPROVED)")
    @PostMapping("/applications/{contributorId}/approve")
    public AdminApplicationView approve(@PathVariable UUID contributorId) {
        return view(service.approve(contributorId, AdminActor.current()));
    }

    @Operation(summary = "Decline an application (PENDING -> DECLINED)")
    @PostMapping("/applications/{contributorId}/decline")
    public AdminApplicationView decline(@PathVariable UUID contributorId) {
        return view(service.decline(contributorId, AdminActor.current()));
    }

    @Operation(summary = "Revoke an approved contributor (APPROVED -> REVOKED)")
    @PostMapping("/contributors/{contributorId}/revoke")
    public AdminApplicationView revoke(@PathVariable UUID contributorId) {
        return view(service.revoke(contributorId, AdminActor.current()));
    }

    @Operation(summary = "Read the audit log, newest first",
            description = "Optional exact-match filters objectType (e.g. CONTRIBUTOR, SAMPLE, AD_EXEMPTION) and "
                    + "objectId. limit: default 50, values above 200 are capped at 200.")
    @GetMapping("/audit")
    public List<AuditEntryView> audit(@RequestParam(required = false) String objectType,
                                      @RequestParam(required = false) String objectId,
                                      @RequestParam(required = false) String limit) {
        int n = AdminParams.limit(limit);
        return auditLog.search(blankToNull(objectType), blankToNull(objectId), Limit.of(n)).stream()
                .map(AdminController::auditView).toList();
    }

    private static String blankToNull(String s) {
        return s == null || s.isBlank() ? null : s.strip();
    }

    private static AuditEntryView auditView(AuditLogEntry e) {
        return new AuditEntryView(e.getId(), e.getActor(), e.getAction(), e.getObjectType(), e.getObjectId(),
                e.getBeforeJson(), e.getAfterJson(), e.getCreatedAt().toString());
    }

    private static AdminApplicationView view(Contributor c) {
        return new AdminApplicationView(c.getContributorId(), c.getNote(), c.getStatus().name(),
                c.getCreatedAt().toString(), c.getUpdatedAt().toString());
    }
}
