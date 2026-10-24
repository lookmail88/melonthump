package dev.melonthump.store;

import java.sql.Timestamp;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

/** PostgreSQL access for the app_event ledger (design doc §3.3/§4). */
@Component
public class AppEventStore {

    private final JdbcTemplate jdbc;

    public AppEventStore(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /** One validated event, ready to insert. received_ts is stamped by the DB default. */
    public record EventRow(UUID eventId, UUID installId, UUID sessionId, String type,
                           String verdict, String slot, String unitSource, Integer errorCode,
                           Instant clientTs) {
    }

    /** Minimal projection the summary aggregation needs. */
    public record ReceivedEvent(Instant receivedTs, String type, String verdict, UUID installId) {
    }

    /**
     * Inserts the batch, skipping rows whose event_id is already stored
     * (upload retries are idempotent). Returns how many rows were new.
     */
    public int insertIgnoringDuplicates(List<EventRow> rows) {
        int inserted = 0;
        for (EventRow row : rows) {
            try {
                jdbc.update("INSERT INTO app_event (event_id, install_id, session_id, type, verdict, "
                                + "slot, unit_source, error_code, client_ts) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                        row.eventId(), row.installId(), row.sessionId(), row.type(), row.verdict(),
                        row.slot(), row.unitSource(), row.errorCode(), Timestamp.from(row.clientTs()));
                inserted++;
            } catch (DuplicateKeyException duplicate) {
                // Same event uploaded twice: count it once, say nothing.
            }
        }
        return inserted;
    }

    /** All events received in [fromInclusive, toExclusive), oldest first. */
    public List<ReceivedEvent> eventsReceivedBetween(Instant fromInclusive, Instant toExclusive) {
        return jdbc.query(
                "SELECT received_ts, type, verdict, install_id FROM app_event "
                        + "WHERE received_ts >= ? AND received_ts < ? ORDER BY received_ts",
                (rs, rowNum) -> new ReceivedEvent(
                        rs.getTimestamp("received_ts").toInstant(),
                        rs.getString("type"),
                        rs.getString("verdict"),
                        rs.getObject("install_id", UUID.class)),
                Timestamp.from(fromInclusive), Timestamp.from(toExclusive));
    }

    public long countAll() {
        Long count = jdbc.queryForObject("SELECT COUNT(*) FROM app_event", Long.class);
        return count == null ? 0 : count;
    }
}
