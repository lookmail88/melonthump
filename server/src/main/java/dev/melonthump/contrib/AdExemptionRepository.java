package dev.melonthump.contrib;

import jakarta.persistence.LockModeType;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.Repository;
import org.springframework.data.repository.query.Param;

/** Owner ad-exemption allowlist by install id (V6). */
public interface AdExemptionRepository extends Repository<AdExemption, String> {

    <S extends AdExemption> S saveAndFlush(S exemption);

    Optional<AdExemption> findById(String installId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select e from AdExemption e where e.installId = :id")
    Optional<AdExemption> findForUpdate(@Param("id") String installId);

    boolean existsById(String installId);

    List<AdExemption> findAllByOrderByCreatedAtDescInstallIdAsc();

    void delete(AdExemption exemption);

    void flush();
}
