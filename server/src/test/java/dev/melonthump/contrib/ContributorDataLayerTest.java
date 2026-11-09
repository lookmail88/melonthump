package dev.melonthump.contrib;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * The V4 schema and JPA mappings at the repository/service layer:
 * ledger balance sums, sample persistence (completeness derivation,
 * taste tags, nullable record fields, CHECK constraints), audit
 * immutability, and race-safe idempotent application submit.
 */
@SpringBootTest
@ActiveProfiles("test")
@TestPropertySource(properties =
        "spring.datasource.url=jdbc:h2:mem:melonthump-contrib-store;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1")
class ContributorDataLayerTest {

    @Autowired
    private ContributionService service;

    @Autowired
    private AdFreeLedgerRepository ledger;

    @Autowired
    private SampleRepository samples;

    @Autowired
    private AuditLogRepository auditLog;

    @Autowired
    private AuditLogService auditService;

    @Autowired
    private JdbcTemplate jdbc;

    @Autowired
    private TransactionTemplate tx;

    private UUID contributor() {
        UUID id = UUID.randomUUID();
        service.submitApplication(id, "test contributor");
        return id;
    }

    @Test
    void balanceIsSumOfDeltasAndZeroWithoutRows() {
        UUID id = contributor();
        assertEquals(0, ledger.balanceOf(id));
        assertEquals(0, ledger.balanceOf(UUID.randomUUID()), "unknown contributor has a zero balance");
        tx.executeWithoutResult(s -> {
            ledger.save(new AdFreeLedgerEntry(id, 5, LedgerReason.SAMPLE_APPROVED, "10"));
            ledger.save(new AdFreeLedgerEntry(id, 20, LedgerReason.ADMIN_GRANT, null));
            ledger.save(new AdFreeLedgerEntry(id, -5, LedgerReason.VOID_CLAWBACK, "10"));
            ledger.save(new AdFreeLedgerEntry(id, -4, LedgerReason.ADMIN_REVOKE, null));
        });
        assertEquals(16, ledger.balanceOf(id));
        assertEquals(16, service.standing(id).adFreeBalance());

        List<AdFreeLedgerEntry> rows = ledger.findByContributorIdOrderByIdAsc(id);
        assertEquals(4, rows.size());
        assertEquals(LedgerReason.ADMIN_GRANT, rows.get(1).getReason());
        assertNull(rows.get(1).getReferenceId());
        assertTrue(rows.get(0).getCreatedAt() != null);

        UUID other = contributor();
        tx.executeWithoutResult(s -> ledger.save(new AdFreeLedgerEntry(other, 3, LedgerReason.ADMIN_GRANT, null)));
        assertEquals(16, ledger.balanceOf(id), "balances are per contributor");
        assertEquals(3, ledger.balanceOf(other));
    }

    @Test
    void ledgerRequiresExistingContributor() {
        assertThrows(DataIntegrityViolationException.class, () -> tx.executeWithoutResult(s ->
                ledger.save(new AdFreeLedgerEntry(UUID.randomUUID(), 5, LedgerReason.ADMIN_GRANT, null))));
    }

    @Test
    void sampleRoundTripsAllRecordFields() {
        UUID id = contributor();
        Sample saved = tx.execute(s -> {
            Sample sample = new Sample(id, Variety.BLACK_BEAUTY);
            sample.setWeight(5400, WeightProvenance.SCALE_MEASURED);
            sample.setSource("farmers market");
            sample.setMelonDate(LocalDate.of(2026, 7, 4));
            sample.setParts(true, true, true, true);
            sample.setScore(92);
            sample.setTasteTags(List.of("crisp", "juicy", "sweet"));
            sample.setBandTruth(BandTruth.RIPE);
            return samples.save(sample);
        });
        Sample loaded = samples.findById(saved.getId()).orElseThrow();
        assertEquals(id, loaded.getContributorId());
        assertEquals(Variety.BLACK_BEAUTY, loaded.getVariety());
        assertEquals(5400, loaded.getWeightGrams());
        assertEquals(WeightProvenance.SCALE_MEASURED, loaded.getWeightProvenance());
        assertEquals("farmers market", loaded.getSource());
        assertEquals(LocalDate.of(2026, 7, 4), loaded.getMelonDate());
        assertTrue(loaded.isComplete());
        assertEquals(92, loaded.getScore());
        assertEquals(List.of("crisp", "juicy", "sweet"), loaded.getTasteTags());
        assertEquals(BandTruth.RIPE, loaded.getBandTruth());
        assertEquals(SampleStatus.SUBMITTED, loaded.getStatus());
        assertNull(loaded.getReturnReason());
        assertEquals("[\"crisp\",\"juicy\",\"sweet\"]",
                jdbc.queryForObject("SELECT taste_tags FROM samples WHERE id = ?", String.class, saved.getId()));
    }

    @Test
    void sampleWithOnlyRequiredFieldsIsIncomplete() {
        UUID id = contributor();
        Sample saved = tx.execute(s -> {
            Sample sample = new Sample(id, Variety.OTHER);
            sample.setParts(true, true, false, true);
            return samples.save(sample);
        });
        Sample loaded = samples.findById(saved.getId()).orElseThrow();
        assertFalse(loaded.isComplete(), "missing cut-open photo means incomplete");
        assertNull(loaded.getWeightGrams());
        assertNull(loaded.getWeightProvenance());
        assertNull(loaded.getScore());
        assertNull(loaded.getTasteTags());
        assertNull(loaded.getBandTruth());
        assertNull(loaded.getMelonDate());

        // Completing the record later re-derives the flag; voiding is a status, not a delete.
        tx.executeWithoutResult(s -> {
            Sample s2 = samples.findById(saved.getId()).orElseThrow();
            s2.setParts(true, true, true, true);
            s2.setStatus(SampleStatus.RETURNED);
            s2.setReturnReason("cut-open photo is blurry");
            samples.save(s2);
        });
        Sample fixed = samples.findById(saved.getId()).orElseThrow();
        assertTrue(fixed.isComplete());
        assertEquals(SampleStatus.RETURNED, fixed.getStatus());
        assertEquals("cut-open photo is blurry", fixed.getReturnReason());
        assertEquals(1, samples.findByContributorIdOrderByCreatedAtAscIdAsc(id).size());
    }

    @Test
    void schemaChecksRejectBadValues() {
        UUID id = contributor();
        assertThrows(DataIntegrityViolationException.class, () -> jdbc.update(
                "INSERT INTO samples (contributor_id, variety, status, score) VALUES (?, 'SEEDLESS', 'SUBMITTED', 101)", id));
        assertThrows(DataIntegrityViolationException.class, () -> jdbc.update(
                "INSERT INTO samples (contributor_id, variety, status) VALUES (?, 'CANTALOUPE', 'SUBMITTED')", id));
        assertThrows(DataIntegrityViolationException.class, () -> jdbc.update(
                "INSERT INTO samples (contributor_id, variety, status, complete) VALUES (?, 'SEEDLESS', 'SUBMITTED', TRUE)", id));
        assertThrows(DataIntegrityViolationException.class, () -> jdbc.update(
                "INSERT INTO samples (contributor_id, variety, status) VALUES (?, 'SEEDLESS', 'DELETED')", id));
        assertThrows(DataIntegrityViolationException.class, () -> jdbc.update(
                "INSERT INTO contributors (contributor_id, note, status) VALUES (?, 'x', 'ACTIVE')", UUID.randomUUID()));
        assertThrows(IllegalArgumentException.class, () -> new Sample(id, Variety.SEEDED).setScore(-1));
    }

    @Test
    void auditEntriesAreImmutable() {
        UUID id = contributor();
        List<AuditLogEntry> rows = auditLog.findByObjectTypeAndObjectIdOrderByIdAsc(
                AuditLogService.OBJECT_CONTRIBUTOR, id.toString());
        assertEquals(1, rows.size());
        AuditLogEntry entry = rows.get(0);
        assertEquals(ContributionService.ACTION_SUBMITTED, entry.getAction());
        assertEquals(id.toString(), entry.getActor());
        assertTrue(entry.getCreatedAt() != null);

        // Hibernate ignores updates to an @Immutable entity: re-saving a loaded row changes nothing.
        tx.executeWithoutResult(s -> auditLog.save(entry));
        assertEquals(1, auditLog.findByObjectTypeAndObjectIdOrderByIdAsc(
                AuditLogService.OBJECT_CONTRIBUTOR, id.toString()).size());
    }

    @Test
    void auditWriteRequiresSurroundingTransaction() {
        assertThrows(org.springframework.transaction.IllegalTransactionStateException.class,
                () -> auditService.record("owner", "X", "CONTRIBUTOR", "x", null, null));
    }

    @Test
    void concurrentSubmitsCreateExactlyOneApplication() throws Exception {
        UUID id = UUID.randomUUID();
        int threads = 8;
        ExecutorService pool = Executors.newFixedThreadPool(threads);
        try {
            List<Callable<ContributionService.Submission>> calls = new ArrayList<>();
            for (int i = 0; i < threads; i++) {
                String note = "note " + i;
                calls.add(() -> service.submitApplication(id, note));
            }
            int created = 0;
            for (Future<ContributionService.Submission> f : pool.invokeAll(calls)) {
                ContributionService.Submission s = f.get();
                assertEquals(id, s.contributor().getContributorId());
                if (s.created()) {
                    created++;
                }
            }
            assertEquals(1, created);
        } finally {
            pool.shutdownNow();
        }
        assertEquals(1, jdbc.queryForObject(
                "SELECT COUNT(*) FROM contributors WHERE contributor_id = ?", Integer.class, id));
        assertEquals(1, jdbc.queryForObject(
                "SELECT COUNT(*) FROM audit_log WHERE object_id = ?", Integer.class, id.toString()));
    }
}
