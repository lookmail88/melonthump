package dev.melonthump.contrib;

import java.util.List;
import org.springframework.data.domain.Limit;
import org.springframework.data.repository.Repository;

/** Append-only: insert and read, no update or delete methods. */
public interface AuditLogRepository extends Repository<AuditLogEntry, Long> {

    AuditLogEntry save(AuditLogEntry entry);

    List<AuditLogEntry> findByObjectTypeAndObjectIdOrderByIdAsc(String objectType, String objectId);

    List<AuditLogEntry> findAllByOrderByIdAsc();

    long count();

    // Admin audit read (S3), newest first; one derived query per filter combination.
    List<AuditLogEntry> findAllByOrderByIdDesc(Limit limit);

    List<AuditLogEntry> findByObjectTypeOrderByIdDesc(String objectType, Limit limit);

    List<AuditLogEntry> findByObjectIdOrderByIdDesc(String objectId, Limit limit);

    List<AuditLogEntry> findByObjectTypeAndObjectIdOrderByIdDesc(String objectType, String objectId, Limit limit);

    /** Newest first; null filters match anything. */
    default List<AuditLogEntry> search(String objectType, String objectId, Limit limit) {
        if (objectType == null && objectId == null) {
            return findAllByOrderByIdDesc(limit);
        }
        if (objectId == null) {
            return findByObjectTypeOrderByIdDesc(objectType, limit);
        }
        if (objectType == null) {
            return findByObjectIdOrderByIdDesc(objectId, limit);
        }
        return findByObjectTypeAndObjectIdOrderByIdDesc(objectType, objectId, limit);
    }
}
