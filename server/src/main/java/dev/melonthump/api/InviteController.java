package dev.melonthump.api;

import com.fasterxml.jackson.databind.ObjectMapper;
import dev.melonthump.attest.AssertionService;
import dev.melonthump.attest.AttestException;
import dev.melonthump.dto.InviteDtos.AttributeRequest;
import dev.melonthump.dto.InviteDtos.AttributeResponse;
import dev.melonthump.dto.InviteDtos.ClaimRequest;
import dev.melonthump.dto.InviteDtos.ClaimResponse;
import dev.melonthump.dto.InviteDtos.CodeResponse;
import dev.melonthump.dto.InviteDtos.ConfirmResponse;
import dev.melonthump.dto.InviteDtos.InstallRequest;
import dev.melonthump.dto.InviteDtos.StatusResponse;
import dev.melonthump.store.AttestStore;
import dev.melonthump.store.InviteStore;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import java.io.IOException;
import java.util.Set;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

/**
 * Invite attribution and rewards (design doc 1.2.0 §3). Every endpoint
 * is App Attest gated exactly like the stats upload: the assertion
 * covers the exact request body bytes, and for a real assertion the
 * body's installId must be the install the key was enrolled for. The
 * dev-only simulator bypass trusts the body.
 *
 * Flow: inviter fetches /code and shares it -> invitee posts /attribute
 * (link or typed code) -> invitee posts /confirm after their first
 * completed thump analysis -> both sides /claim their +5 once.
 */
@RestController
@RequestMapping("/api/v1/invite")
@Tag(name = "invite", description = "Invite codes, attribution, confirmation and reward claims")
public class InviteController {

    private static final Set<String> SOURCES = Set.of("link", "code");

    private final InviteStore invites;
    private final AttestStore attestStore;
    private final AssertionService assertions;
    private final ObjectMapper objectMapper;
    private final int rewardCredits;
    private final int cap;

    public InviteController(InviteStore invites, AttestStore attestStore, AssertionService assertions,
                            ObjectMapper objectMapper,
                            @Value("${melonthump.invite.reward-credits:5}") int rewardCredits,
                            @Value("${melonthump.invite.cap:10}") int cap) {
        this.invites = invites;
        this.attestStore = attestStore;
        this.assertions = assertions;
        this.objectMapper = objectMapper;
        this.rewardCredits = rewardCredits;
        this.cap = cap;
    }

    /** The caller as established by the gate. keyId is null only on the dev bypass. */
    private record Caller(UUID installId, String keyId) {
    }

    private Caller gate(byte[] rawBody, UUID claimedInstall, String keyId, String assertion,
                        String challenge, String bypass) throws AttestException {
        if (assertions.isDebugBypass(bypass)) {
            requireInstall(claimedInstall);
            return new Caller(claimedInstall, null);
        }
        AssertionService.Verified verified = assertions.verify(keyId, assertion, challenge, rawBody);
        requireInstall(claimedInstall);
        UUID enrolledInstall = attestStore.findKey(verified.keyId())
                .map(AttestStore.AttestedKey::installId)
                .orElseThrow(() -> new AttestException("key not enrolled"));
        if (!enrolledInstall.equals(claimedInstall)) {
            throw new AttestException("installId does not match the attested key");
        }
        return new Caller(claimedInstall, verified.keyId());
    }

    private static void requireInstall(UUID installId) {
        if (installId == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "installId is required");
        }
    }

    private <T> T parse(byte[] rawBody, Class<T> type) {
        try {
            return objectMapper.readValue(rawBody, type);
        } catch (IOException e) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "body is not valid JSON");
        }
    }

    @Operation(summary = "Get (or issue) the caller's invite code")
    @PostMapping("/code")
    public CodeResponse code(@RequestBody byte[] rawBody,
                             @RequestHeader(value = "X-Key-Id", required = false) String keyId,
                             @RequestHeader(value = "X-Assertion", required = false) String assertion,
                             @RequestHeader(value = "X-Challenge", required = false) String challenge,
                             @RequestHeader(value = AssertionService.BYPASS_HEADER, required = false) String bypass)
            throws AttestException {
        InstallRequest request = parse(rawBody, InstallRequest.class);
        Caller caller = gate(rawBody, request.installId(), keyId, assertion, challenge, bypass);
        return new CodeResponse(invites.getOrCreateCode(caller.installId()));
    }

    @Operation(summary = "Record that the caller (invitee) arrived via an invite link or code",
            description = "Opening a link is attribution only, never a confirmation. 404 unknown code; "
                    + "409 self-invite, already attributed to another inviter, device already counted, "
                    + "or the install already completed an analysis.")
    @PostMapping("/attribute")
    public ResponseEntity<AttributeResponse> attribute(@RequestBody byte[] rawBody,
                                       @RequestHeader(value = "X-Key-Id", required = false) String keyId,
                                       @RequestHeader(value = "X-Assertion", required = false) String assertion,
                                       @RequestHeader(value = "X-Challenge", required = false) String challenge,
                                       @RequestHeader(value = AssertionService.BYPASS_HEADER, required = false) String bypass)
            throws AttestException {
        AttributeRequest request = parse(rawBody, AttributeRequest.class);
        Caller caller = gate(rawBody, request.installId(), keyId, assertion, challenge, bypass);
        String code = InviteStore.normalizeCode(request.code());
        if (code == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "malformed invite code");
        }
        if (request.source() == null || !SOURCES.contains(request.source())) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "source must be link or code");
        }
        // Refusals carry their reason in the body ({"status": ...}) so the
        // app can tell the user why (self-invite, already invited, ...).
        return switch (invites.attribute(caller.installId(), caller.keyId(), code, request.source())) {
            case ATTRIBUTED -> ResponseEntity.ok(new AttributeResponse("attributed"));
            case ALREADY_ATTRIBUTED -> ResponseEntity.ok(new AttributeResponse("already_attributed"));
            case UNKNOWN_CODE -> refuse(HttpStatus.NOT_FOUND, "unknown_code");
            case SELF_INVITE -> refuse(HttpStatus.CONFLICT, "self_invite");
            case ATTRIBUTED_ELSEWHERE -> refuse(HttpStatus.CONFLICT, "already_invited");
            case DEVICE_ALREADY_COUNTED -> refuse(HttpStatus.CONFLICT, "device_already_counted");
            case ALREADY_ACTIVE -> refuse(HttpStatus.CONFLICT, "already_active");
        };
    }

    private static ResponseEntity<AttributeResponse> refuse(HttpStatus status, String reason) {
        return ResponseEntity.status(status).body(new AttributeResponse(reason));
    }

    @Operation(summary = "Confirm the caller's invite after their first completed thump analysis (idempotent)")
    @PostMapping("/confirm")
    public ConfirmResponse confirm(@RequestBody byte[] rawBody,
                                   @RequestHeader(value = "X-Key-Id", required = false) String keyId,
                                   @RequestHeader(value = "X-Assertion", required = false) String assertion,
                                   @RequestHeader(value = "X-Challenge", required = false) String challenge,
                                   @RequestHeader(value = AssertionService.BYPASS_HEADER, required = false) String bypass)
            throws AttestException {
        InstallRequest request = parse(rawBody, InstallRequest.class);
        Caller caller = gate(rawBody, request.installId(), keyId, assertion, challenge, bypass);
        InviteStore.ConfirmOutcome outcome = invites.confirm(caller.installId(), cap);
        String status = switch (outcome.status()) {
            case CONFIRMED -> "confirmed";
            case ALREADY_CONFIRMED -> "already_confirmed";
            case NOT_INVITED -> "not_invited";
        };
        return new ConfirmResponse(status, outcome.rewarded());
    }

    @Operation(summary = "The caller's invite standing (as inviter and as invitee)")
    @PostMapping("/status")
    public StatusResponse status(@RequestBody byte[] rawBody,
                                 @RequestHeader(value = "X-Key-Id", required = false) String keyId,
                                 @RequestHeader(value = "X-Assertion", required = false) String assertion,
                                 @RequestHeader(value = "X-Challenge", required = false) String challenge,
                                 @RequestHeader(value = AssertionService.BYPASS_HEADER, required = false) String bypass)
            throws AttestException {
        InstallRequest request = parse(rawBody, InstallRequest.class);
        Caller caller = gate(rawBody, request.installId(), keyId, assertion, challenge, bypass);
        InviteStore.Status s = invites.status(caller.installId());
        return new StatusResponse(s.code(), s.confirmedInvites(), s.rewardedInvites(), cap, rewardCredits,
                s.unclaimedInviterRewards() * rewardCredits, s.invited(), s.inviteeConfirmed(),
                s.inviteeRewardClaimable() ? rewardCredits : 0);
    }

    @Operation(summary = "Claim every unclaimed invite reward once; idempotent per claimId",
            description = "The client adds the returned credits to its on-device CreditWallet "
                    + "exactly once per claimId.")
    @PostMapping("/claim")
    public ClaimResponse claim(@RequestBody byte[] rawBody,
                               @RequestHeader(value = "X-Key-Id", required = false) String keyId,
                               @RequestHeader(value = "X-Assertion", required = false) String assertion,
                               @RequestHeader(value = "X-Challenge", required = false) String challenge,
                               @RequestHeader(value = AssertionService.BYPASS_HEADER, required = false) String bypass)
            throws AttestException {
        ClaimRequest request = parse(rawBody, ClaimRequest.class);
        Caller caller = gate(rawBody, request.installId(), keyId, assertion, challenge, bypass);
        if (request.claimId() == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "claimId is required");
        }
        InviteStore.ClaimOutcome outcome = invites.claim(caller.installId(), request.claimId());
        int credits = outcome.inviterRewards() * rewardCredits + (outcome.inviteeReward() ? rewardCredits : 0);
        return new ClaimResponse(request.claimId(), credits, outcome.inviterRewards(), outcome.inviteeReward());
    }
}
