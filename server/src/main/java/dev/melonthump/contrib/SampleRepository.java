package dev.melonthump.contrib;

import jakarta.persistence.LockModeType;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Limit;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.Repository;
import org.springframework.data.repository.query.Param;

/**
 * Samples. Owner-side removal is void-marking (design doc 2.0 §7 item
 * 10); the only delete path is the contributor's own withdrawal of a
 * not-yet-approved sample (§7 item 8 (ii) true deletion, S2), which
 * removes the row together with its files and leaves an audit row.
 */
public interface SampleRepository extends Repository<Sample, Long> {

    Sample save(Sample sample);

    Sample saveAndFlush(Sample sample);

    Optional<Sample> findById(Long id);

    /** Row lock for append / withdraw, so concurrent requests on one sample serialize. */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select s from Sample s where s.id = :id")
    Optional<Sample> findForUpdate(@Param("id") Long id);

    List<Sample> findByContributorIdOrderByCreatedAtAscIdAsc(UUID contributorId);

    List<Sample> findByContributorIdOrderByCreatedAtDescIdDesc(UUID contributorId);

    List<Sample> findByStatusOrderByCreatedAtAscIdAsc(SampleStatus status);

    // Admin list (S3), newest first. One derived query per filter combination
    // rather than "(:p is null or ...)", which PostgreSQL cannot type for a
    // null UUID parameter.
    List<Sample> findAllByOrderByCreatedAtDescIdDesc(Limit limit);

    List<Sample> findByStatusOrderByCreatedAtDescIdDesc(SampleStatus status, Limit limit);

    List<Sample> findByContributorIdOrderByCreatedAtDescIdDesc(UUID contributorId, Limit limit);

    List<Sample> findByStatusAndContributorIdOrderByCreatedAtDescIdDesc(SampleStatus status, UUID contributorId,
                                                                       Limit limit);

    void delete(Sample sample);

    void flush();
}
