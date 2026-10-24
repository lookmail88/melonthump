package dev.melonthump.api;

import com.fasterxml.jackson.databind.ObjectMapper;
import dev.melonthump.attest.AssertionService;
import dev.melonthump.attest.AttestException;
import dev.melonthump.dto.StatsDtos.EventDto;
import dev.melonthump.dto.StatsDtos.EventsRequest;
import dev.melonthump.dto.StatsDtos.EventsResponse;
import dev.melonthump.dto.StatsDtos.SummaryDay;
import dev.melonthump.dto.StatsDtos.SummaryResponse;
import dev.melonthump.store.AppEventStore;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import java.io.IOException;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

/**
 * Usage-stats surface (design doc §3.3/§3.4): attested batch upload
 * plus the admin-token reconciliation summary.
 */
@RestController
@RequestMapping("/api/v1/stats")
@Tag(name = "stats", description = "Anonymous usage events (ad ledger + analysis counts)")
public class StatsController {

    static final int MAX_BATCH = 100;
    static final ZoneId REPORT_ZONE = ZoneId.of("America/Los_Angeles");

    private static final Set<String> EVENT_TYPES = Set.of(
            "analysis_completed", "ad_requested", "ad_loaded", "ad_load_failed",
            "ad_shown", "ad_rewarded", "ad_dismissed");
    private static final Set<String> VERDICTS = Set.of("UNRIPE", "RIPE", "OVERRIPE", "UNKNOWN");
    private static final Set<String> UNIT_SOURCES = Set.of("server", "test_fallback");

    private final AppEventStore events;
    private final AssertionService assertions;
    private final ObjectMapper objectMapper;
    private final String adminToken;

    public StatsController(AppEventStore events, AssertionService assertions, ObjectMapper objectMapper,
                           @Value("${melonthump.stats.admin-token:}") String adminToken) {
        this.events = events;
        this.assertions = assertions;
        this.objectMapper = objectMapper;
        this.adminToken = adminToken;
    }

    @Operation(summary = "Upload a batch of usage events (requires a valid App Attest assertion)",
            description = "Headers: X-Key-Id, X-Assertion, X-Challenge. The assertion covers the exact "
                    + "request body bytes. Uploads are idempotent on each event's eventId.")
    @PostMapping("/events")
    @ResponseStatus(HttpStatus.ACCEPTED)
    public EventsResponse upload(
            @RequestBody byte[] rawBody,
            @RequestHeader(value = "X-Key-Id", required = false) String keyId,
            @RequestHeader(value = "X-Assertion", required = false) String assertion,
            @RequestHeader(value = "X-Challenge", required = false) String challenge,
            @RequestHeader(value = AssertionService.BYPASS_HEADER, required = false) String bypass)
            throws AttestException {
        if (!assertions.isDebugBypass(bypass)) {
            assertions.verify(keyId, assertion, challenge, rawBody);
        }
        EventsRequest request = parse(rawBody);
        List<AppEventStore.EventRow> rows = validate(request);
        return new EventsResponse(events.insertIgnoringDuplicates(rows));
    }

    @Operation(summary = "Per-day reconciliation summary (America/Los_Angeles), admin token required",
            description = "Header X-Admin-Token must match MELONTHUMP_STATS_ADMIN_TOKEN; "
                    + "when no token is configured the endpoint always refuses.")
    @GetMapping("/summary")
    public SummaryResponse summary(
            @RequestParam(defaultValue = "30") int days,
            @RequestHeader(value = "X-Admin-Token", required = false) String token) {
        if (adminToken.isBlank() || token == null
                || !java.security.MessageDigest.isEqual(
                        adminToken.getBytes(java.nio.charset.StandardCharsets.UTF_8),
                        token.getBytes(java.nio.charset.StandardCharsets.UTF_8))) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "admin token required");
        }
        int window = Math.max(1, Math.min(days, 90));
        LocalDate today = LocalDate.now(REPORT_ZONE);
        LocalDate firstDay = today.minusDays(window - 1L);
        Instant from = firstDay.atStartOfDay(REPORT_ZONE).toInstant();
        Instant to = today.plusDays(1).atStartOfDay(REPORT_ZONE).toInstant();

        Map<LocalDate, DayAccumulator> byDay = new LinkedHashMap<>();
        for (int i = 0; i < window; i++) {
            byDay.put(firstDay.plusDays(i), new DayAccumulator());
        }
        for (AppEventStore.ReceivedEvent event : events.eventsReceivedBetween(from, to)) {
            DayAccumulator acc = byDay.get(event.receivedTs().atZone(REPORT_ZONE).toLocalDate());
            if (acc != null) {
                acc.add(event);
            }
        }
        List<SummaryDay> out = new ArrayList<>();
        byDay.forEach((date, acc) -> out.add(acc.toDay(date)));
        return new SummaryResponse(out);
    }

    // ---- validation ------------------------------------------------------

    private EventsRequest parse(byte[] rawBody) {
        try {
            return objectMapper.readValue(rawBody, EventsRequest.class);
        } catch (IOException e) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "body is not valid events JSON");
        }
    }

    private List<AppEventStore.EventRow> validate(EventsRequest request) {
        if (request.installId() == null || request.events() == null || request.events().isEmpty()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "installId and a non-empty events list are required");
        }
        if (request.events().size() > MAX_BATCH) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "batch exceeds " + MAX_BATCH + " events");
        }
        List<AppEventStore.EventRow> rows = new ArrayList<>();
        for (EventDto event : request.events()) {
            rows.add(validateEvent(request, event));
        }
        return rows;
    }

    private AppEventStore.EventRow validateEvent(EventsRequest request, EventDto event) {
        if (event.eventId() == null || event.type() == null || !EVENT_TYPES.contains(event.type())) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "unknown or missing event type");
        }
        if (event.clientTs() <= 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "clientTs must be epoch milliseconds");
        }
        String verdict = null;
        String slot = null;
        String unitSource = null;
        Integer errorCode = null;
        switch (event.type()) {
            case "analysis_completed" -> {
                if (event.verdict() == null || !VERDICTS.contains(event.verdict())) {
                    throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "analysis_completed needs a valid verdict");
                }
                verdict = event.verdict();
            }
            case "ad_requested" -> {
                slot = requireSlot(event);
                if (event.unitSource() == null || !UNIT_SOURCES.contains(event.unitSource())) {
                    throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "ad_requested needs unitSource server/test_fallback");
                }
                unitSource = event.unitSource();
            }
            case "ad_load_failed" -> {
                slot = requireSlot(event);
                if (event.errorCode() == null) {
                    throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "ad_load_failed needs errorCode");
                }
                errorCode = event.errorCode();
            }
            default -> slot = requireSlot(event); // ad_loaded / ad_shown / ad_rewarded / ad_dismissed
        }
        return new AppEventStore.EventRow(
                event.eventId(), request.installId(), request.sessionId(), event.type(),
                verdict, slot, unitSource, errorCode, Instant.ofEpochMilli(event.clientTs()));
    }

    private static String requireSlot(EventDto event) {
        if (event.slot() == null || event.slot().isBlank() || event.slot().length() > 32) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "ad events need a slot (logical name, max 32 chars)");
        }
        return event.slot();
    }

    // ---- summary accumulator ----------------------------------------------

    private static final class DayAccumulator {
        private long analyses;
        private final Map<String, Long> verdicts = new LinkedHashMap<>();
        private long adRequested;
        private long adLoaded;
        private long adLoadFailed;
        private long adShown;
        private long adRewarded;
        private long adDismissed;
        private final Set<java.util.UUID> installs = new LinkedHashSet<>();

        void add(AppEventStore.ReceivedEvent event) {
            installs.add(event.installId());
            switch (event.type()) {
                case "analysis_completed" -> {
                    analyses++;
                    if (event.verdict() != null) {
                        verdicts.merge(event.verdict(), 1L, Long::sum);
                    }
                }
                case "ad_requested" -> adRequested++;
                case "ad_loaded" -> adLoaded++;
                case "ad_load_failed" -> adLoadFailed++;
                case "ad_shown" -> adShown++;
                case "ad_rewarded" -> adRewarded++;
                case "ad_dismissed" -> adDismissed++;
                default -> {
                    // Closed set enforced at insert; nothing else can be stored.
                }
            }
        }

        SummaryDay toDay(LocalDate date) {
            return new SummaryDay(date.toString(), analyses, verdicts, adRequested, adLoaded,
                    adLoadFailed, adShown, adRewarded, adDismissed, installs.size());
        }
    }
}
