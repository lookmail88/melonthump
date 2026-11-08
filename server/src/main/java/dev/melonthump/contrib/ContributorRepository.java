package dev.melonthump.contrib;

import jakarta.persistence.LockModeType;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.Repository;
import org.springframework.data.repository.query.Param;

/** Contributors. No delete path: a contributor is switched off (REVOKED), never removed. */
public interface ContributorRepository extends Repository<Contributor, UUID> {

    Contributor save(Contributor contributor);

    <S extends Contributor> S saveAndFlush(S contributor);

    Optional<Contributor> findById(UUID contributorId);

    /** Row-locked read for status transitions, so concurrent admin actions serialize. */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select c from Contributor c where c.contributorId = :id")
    Optional<Contributor> findForUpdate(@Param("id") UUID contributorId);

    List<Contributor> findAllByOrderByCreatedAtAscContributorIdAsc();

    List<Contributor> findByStatusOrderByCreatedAtAscContributorIdAsc(ContributorStatus status);

    long count();
}
