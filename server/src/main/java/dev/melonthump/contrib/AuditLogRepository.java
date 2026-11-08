package dev.melonthump.contrib;

import java.util.List;
import org.springframework.data.repository.Repository;

/** Append-only: insert and read, no update or delete methods. */
public interface AuditLogRepository extends Repository<AuditLogEntry, Long> {

    AuditLogEntry save(AuditLogEntry entry);

    List<AuditLogEntry> findByObjectTypeAndObjectIdOrderByIdAsc(String objectType, String objectId);

    List<AuditLogEntry> findAllByOrderByIdAsc();

    long count();
}
