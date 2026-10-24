package dev.melonthump.api;

import dev.melonthump.attest.AttestException;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/** Maps App Attest failures to 401 across the attested surface. */
@RestControllerAdvice
public class ApiExceptionHandler {

    @ExceptionHandler(AttestException.class)
    public ResponseEntity<Map<String, String>> attestFailed(AttestException e) {
        return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(Map.of("error", "attestation_failed", "detail", e.getMessage()));
    }
}
