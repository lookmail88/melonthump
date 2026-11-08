package dev.melonthump.api;

import org.springframework.http.HttpStatus;

/**
 * A rejected sample request (bad meta, bad part, file too large),
 * rendered as {@code {"error": <code>, "detail": <message>}}.
 */
public class SampleRequestException extends RuntimeException {

    private final HttpStatus status;
    private final String error;

    public SampleRequestException(HttpStatus status, String error, String detail) {
        super(detail);
        this.status = status;
        this.error = error;
    }

    public static SampleRequestException badMeta(String detail) {
        return new SampleRequestException(HttpStatus.BAD_REQUEST, "invalid_meta", detail);
    }

    public HttpStatus status() {
        return status;
    }

    public String error() {
        return error;
    }
}
