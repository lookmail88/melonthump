package dev.melonthump.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.UUID;

/** Wire shapes for the invite endpoints (design doc 1.2.0 §3). */
public final class InviteDtos {

    private InviteDtos() {
    }

    @Schema(description = "Body for code / confirm / status: just the caller's install")
    public record InstallRequest(
            @Schema(description = "Caller's anonymous install UUID (must match the attested key's install)")
            UUID installId) {
    }

    @Schema(description = "The caller's own invite code")
    public record CodeResponse(
            @Schema(description = "Invite code, 8 characters from an unambiguous alphabet", example = "K7QM2XPA")
            String code) {
    }

    @Schema(description = "Invitee attribution: the invitee opened an invite link or typed a code")
    public record AttributeRequest(
            UUID installId,
            @Schema(description = "Inviter's code (case-insensitive; spaces and dashes ignored)")
            String code,
            @Schema(description = "How the code arrived: link / code")
            String source) {
    }

    @Schema(description = "Attribution outcome")
    public record AttributeResponse(
            @Schema(description = "attributed / already_attributed")
            String status) {
    }

    @Schema(description = "Confirmation outcome (invitee completed their first thump analysis)")
    public record ConfirmResponse(
            @Schema(description = "confirmed / already_confirmed / not_invited")
            String status,
            @Schema(description = "True when the confirmation is within the inviter's cap and carries rewards")
            boolean rewarded) {
    }

    @Schema(description = "Invite standing of the caller, both as inviter and as invitee")
    public record StatusResponse(
            @Schema(description = "Caller's own code, null when none issued yet", nullable = true)
            String code,
            @Schema(description = "Confirmed invites (including any past the cap)")
            int confirmedInvites,
            @Schema(description = "Confirmed invites that carry rewards (at most cap)")
            int rewardedInvites,
            @Schema(description = "Per-inviter cap on rewarded invites", example = "10")
            int cap,
            @Schema(description = "Credits per reward, each side", example = "5")
            int rewardCredits,
            @Schema(description = "Unclaimed inviter credits")
            int inviterCreditsClaimable,
            @Schema(description = "True when this install was attributed to an inviter")
            boolean invited,
            @Schema(description = "True when this install's own invite was confirmed")
            boolean inviteeConfirmed,
            @Schema(description = "Unclaimed invitee credits")
            int inviteeCreditsClaimable) {
    }

    @Schema(description = "Reward claim; claimId makes a retried claim idempotent")
    public record ClaimRequest(
            UUID installId,
            @Schema(description = "Client-generated UUID; re-sending the same claimId returns the same result")
            UUID claimId) {
    }

    @Schema(description = "Credits the client adds to its on-device wallet for this claimId")
    public record ClaimResponse(
            UUID claimId,
            @Schema(description = "Total credits granted by this claim (inviter + invitee parts)")
            int credits,
            @Schema(description = "Inviter rewards included in this claim")
            int inviterRewards,
            @Schema(description = "True when the invitee reward is included in this claim")
            boolean inviteeReward) {
    }
}
