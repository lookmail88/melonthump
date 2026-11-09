package dev.melonthump.api;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.util.Locale;
import java.util.UUID;
import org.springframework.http.HttpStatus;

/**
 * Shared request parsing for the S3 admin endpoints. Every rejection is a
 * 400 rendered as {@code {"error": "invalid_request", "detail": …}}.
 */
final class AdminParams {

    static final int DEFAULT_LIMIT = 50;
    static final int MAX_LIMIT = 200;

    private AdminParams() {
    }

    static SampleRequestException bad(String detail) {
        return new SampleRequestException(HttpStatus.BAD_REQUEST, "invalid_request", detail);
    }

    /** Absent → 50; a positive integer above 200 is capped at 200; anything else → 400. */
    static int limit(String raw) {
        if (raw == null || raw.isBlank()) {
            return DEFAULT_LIMIT;
        }
        try {
            int v = Integer.parseInt(raw.strip());
            if (v < 1) {
                throw bad("limit must be a positive integer");
            }
            return Math.min(v, MAX_LIMIT);
        } catch (NumberFormatException e) {
            throw bad("limit must be a positive integer");
        }
    }

    static long positiveId(String raw, String name) {
        try {
            long id = Long.parseLong(raw.strip());
            if (id <= 0) {
                throw new NumberFormatException();
            }
            return id;
        } catch (NumberFormatException | NullPointerException e) {
            throw bad(name + " must be a positive integer");
        }
    }

    static UUID uuid(String raw, String name) {
        try {
            return UUID.fromString(raw.strip());
        } catch (IllegalArgumentException | NullPointerException e) {
            throw bad(name + " must be a UUID");
        }
    }

    static <E extends Enum<E>> E optionalEnum(String raw, Class<E> type, String name) {
        if (raw == null || raw.isBlank()) {
            return null;
        }
        try {
            return Enum.valueOf(type, raw.strip().toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException e) {
            throw bad(name + " is not a valid value");
        }
    }

    /** Parses a JSON object body; missing / empty / non-object / malformed → 400. */
    static JsonNode object(ObjectMapper mapper, byte[] body) {
        if (body == null || body.length == 0) {
            throw bad("a JSON object body is required");
        }
        try {
            JsonNode n = mapper.readTree(body);
            if (n == null || !n.isObject()) {
                throw bad("a JSON object body is required");
            }
            return n;
        } catch (IOException e) {
            throw bad("body is not valid JSON");
        }
    }

    /** A required, non-blank (after trim) string field of at most {@code max} characters, returned trimmed. */
    static String requiredText(JsonNode body, String field, int max) {
        JsonNode n = body.get(field);
        if (n == null || n.isNull() || !n.isTextual() || n.asText().isBlank()) {
            throw bad(field + " is required");
        }
        String v = n.asText().strip();
        if (v.length() > max) {
            throw bad(field + " must be at most " + max + " characters");
        }
        return v;
    }
}
