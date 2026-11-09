package dev.melonthump.contrib;

import java.util.List;
import org.springframework.data.domain.Limit;
import java.util.UUID;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.Repository;
import org.springframework.data.repository.query.Param;

/** Append-only ad-free ledger: insert, read, and the balance sum. */
public interface AdFreeLedgerRepository extends Repository<AdFreeLedgerEntry, Long> {

    AdFreeLedgerEntry save(AdFreeLedgerEntry entry);

    List<AdFreeLedgerEntry> findByContributorIdOrderByIdAsc(UUID contributorId);

    List<AdFreeLedgerEntry> findByContributorIdOrderByIdDesc(UUID contributorId, Limit limit);

    /** Rows of one reason for one reference (e.g. the SAMPLE_APPROVED grant of a sample). */
    List<AdFreeLedgerEntry> findByReferenceIdAndReasonOrderByIdAsc(String referenceId, LedgerReason reason);

    /** Current balance = sum of all deltas; 0 when the contributor has no rows. */
    @Query("select coalesce(sum(e.delta), 0) from AdFreeLedgerEntry e where e.contributorId = :id")
    long balanceOf(@Param("id") UUID contributorId);

    /** Sum of all deltas across every contributor (S4 overview: ad-free units outstanding). */
    @Query("select coalesce(sum(e.delta), 0) from AdFreeLedgerEntry e")
    long totalBalance();
}
