package dev.melonthump.contrib;

import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Read-only counts for the admin overview (design doc 2.0 §7 item 11, page D). */
@Service
public class AdminOverviewService {

    private final ContributorRepository contributors;
    private final SampleRepository samples;
    private final AdFreeLedgerRepository ledger;

    public AdminOverviewService(ContributorRepository contributors, SampleRepository samples,
                                AdFreeLedgerRepository ledger) {
        this.contributors = contributors;
        this.samples = samples;
        this.ledger = ledger;
    }

    /**
     * @param contributors          count per contributor status, every status present
     * @param samples               count per sample status, every status present
     * @param completeSamplesApproved APPROVED samples with all four parts — the count toward the
     *                              30-sample modeling threshold (voided samples never count)
     * @param pendingReview         SUBMITTED samples awaiting the owner
     * @param adFreeOutstanding     sum of every contributor's current ad-free balance
     */
    public record Overview(Map<String, Long> contributors, Map<String, Long> samples, long completeSamplesApproved,
                           long pendingReview, long adFreeOutstanding) {
    }

    @Transactional(readOnly = true)
    public Overview overview() {
        Map<String, Long> c = new LinkedHashMap<>();
        for (ContributorStatus st : ContributorStatus.values()) {
            c.put(st.name(), contributors.countByStatus(st));
        }
        Map<String, Long> s = new LinkedHashMap<>();
        for (SampleStatus st : SampleStatus.values()) {
            s.put(st.name(), samples.countByStatus(st));
        }
        return new Overview(c, s, samples.countByStatusAndComplete(SampleStatus.APPROVED, true),
                s.get(SampleStatus.SUBMITTED.name()), ledger.totalBalance());
    }
}
