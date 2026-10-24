package dev.melonthump.attest;

/** Any App Attest verification failure. Maps to HTTP 401 at the API edge. */
public class AttestException extends Exception {

    public AttestException(String message) {
        super(message);
    }

    public AttestException(String message, Throwable cause) {
        super(message, cause);
    }
}
