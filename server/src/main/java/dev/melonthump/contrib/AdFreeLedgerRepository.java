package dev.melonthump.contrib;

import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.Repository;
import org.springframework.data.repository.query.Param;

/** Append-only ad-free ledger: insert, read, and the balance sum. */
public interface AdFreeLedgerRepository extends Repository<AdFreeLedgerEntry, Long> {

    AdFreeLedgerEntry save(AdFreeLedgerEntry entry);

    List<AdFreeLedgerEntry> findByContributorIdOrderByIdAsc(UUID contributorId);

    /** Current balance = sum of all deltas; 0 when the contributor has no rows. */
    @Query("select coalesce(sum(e.delta), 0) from AdFreeLedgerEntry e where e.contributorId = :id")
    long balanceOf(@Param("id") UUID contributorId);
}
