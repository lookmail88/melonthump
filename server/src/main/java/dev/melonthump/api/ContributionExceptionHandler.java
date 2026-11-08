package dev.melonthump.api;

import dev.melonthump.contrib.ContributionService.ContributorNotFoundException;
import dev.melonthump.contrib.ContributionService.IllegalTransitionException;
import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/**
 * Error mapping for the 2.0 contribution / admin controllers only
 * (scoped by assignableTypes so existing endpoints are untouched):
 * unknown contributor → 404, refused status transition → 409.
 */
@RestControllerAdvice(assignableTypes = {ContributionController.class, AdminController.class})
public class ContributionExceptionHandler {

    @ExceptionHandler(ContributorNotFoundException.class)
    public ResponseEntity<Map<String, String>> notFound(ContributorNotFoundException e) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(body("contributor_not_found", e.getMessage()));
    }

    @ExceptionHandler(IllegalTransitionException.class)
    public ResponseEntity<Map<String, String>> conflict(IllegalTransitionException e) {
        return ResponseEntity.status(HttpStatus.CONFLICT)
                .body(body("illegal_transition", e.getMessage()));
    }

    /** Fixed key order (error, detail) so the body is byte-stable across JVM runs. */
    private static Map<String, String> body(String error, String detail) {
        Map<String, String> m = new LinkedHashMap<>();
        m.put("error", error);
        m.put("detail", detail);
        return m;
    }
}
