package dev.melonthump.contrib;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * Writes the append-only audit log (design doc 2.0 §7 item 11). Joins
 * the caller's transaction (MANDATORY), so an audit row commits or rolls
 * back together with the change it describes.
 */
@Service
public class AuditLogService {

    public static final String OBJECT_CONTRIBUTOR = "CONTRIBUTOR";

    private final AuditLogRepository repository;
    private final ObjectMapper objectMapper;

    public AuditLogService(AuditLogRepository repository, ObjectMapper objectMapper) {
        this.repository = repository;
        this.objectMapper = objectMapper;
    }

    @Transactional(propagation = Propagation.MANDATORY)
    public AuditLogEntry record(String actor, String action, String objectType, String objectId,
                                Map<String, ?> before, Map<String, ?> after) {
        return repository.save(new AuditLogEntry(actor, action, objectType, objectId,
                toJson(before), toJson(after)));
    }

    private String toJson(Map<String, ?> value) {
        if (value == null) {
            return null;
        }
        try {
            return objectMapper.writeValueAsString(value);
        } catch (JsonProcessingException e) {
            throw new IllegalArgumentException("audit payload is not serializable", e);
        }
    }
}
