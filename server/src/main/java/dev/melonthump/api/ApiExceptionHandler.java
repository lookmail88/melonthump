package dev.melonthump.api;

import dev.melonthump.attest.AttestException;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/** Maps App Attest failures to 401 across the attested surface. */
@RestControllerAdvice
public class ApiExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(ApiExceptionHandler.class);

    @ExceptionHandler(AttestException.class)
    public ResponseEntity<Map<String, String>> attestFailed(AttestException e) {
        // The reason is the only way to debug a rejected enrollment;
        // DEBUG keeps it visible on dev and silent on prod (ERROR).
        log.debug("attestation rejected: {}", e.getMessage());
        return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(Map.of("error", "attestation_failed", "detail", e.getMessage()));
    }
}
