package dev.melonthump.api;

import dev.melonthump.contrib.ContributionService.ContributorNotFoundException;
import dev.melonthump.contrib.ContributionService.IllegalTransitionException;
import dev.melonthump.contrib.SampleService.ContributorNotApprovedException;
import dev.melonthump.contrib.SampleService.InvalidSampleException;
import dev.melonthump.contrib.SampleService.SampleForbiddenException;
import dev.melonthump.contrib.SampleService.SampleStateException;
import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/**
 * Error mapping for the 2.0 contribution / admin controllers only
 * (scoped by assignableTypes so existing endpoints are untouched):
 * unknown contributor → 404, refused status transition → 409; for the
 * sample endpoints also: contributor not APPROVED → 403, unknown or
 * foreign sample → 403, sample in a terminal state → 409, request that
 * conflicts with the stored sample's limits → 400.
 */
@RestControllerAdvice(assignableTypes = {ContributionController.class, AdminController.class,
        SampleController.class})
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

    @ExceptionHandler(ContributorNotApprovedException.class)
    public ResponseEntity<Map<String, String>> notApproved(ContributorNotApprovedException e) {
        return ResponseEntity.status(HttpStatus.FORBIDDEN).body(body("contributor_not_approved", e.getMessage()));
    }

    @ExceptionHandler(SampleForbiddenException.class)
    public ResponseEntity<Map<String, String>> sampleForbidden(SampleForbiddenException e) {
        return ResponseEntity.status(HttpStatus.FORBIDDEN).body(body("sample_forbidden", e.getMessage()));
    }

    @ExceptionHandler(SampleStateException.class)
    public ResponseEntity<Map<String, String>> sampleState(SampleStateException e) {
        return ResponseEntity.status(HttpStatus.CONFLICT).body(body("illegal_sample_state", e.getMessage()));
    }

    @ExceptionHandler(InvalidSampleException.class)
    public ResponseEntity<Map<String, String>> invalidSample(InvalidSampleException e) {
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(body("invalid_sample", e.getMessage()));
    }

    @ExceptionHandler(SampleRequestException.class)
    public ResponseEntity<Map<String, String>> badSampleRequest(SampleRequestException e) {
        return ResponseEntity.status(e.status()).body(body(e.error(), e.getMessage()));
    }

    /** Fixed key order (error, detail) so the body is byte-stable across JVM runs. */
    private static Map<String, String> body(String error, String detail) {
        Map<String, String> m = new LinkedHashMap<>();
        m.put("error", error);
        m.put("detail", detail);
        return m;
    }
}
