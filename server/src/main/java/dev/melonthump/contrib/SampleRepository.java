package dev.melonthump.contrib;

import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.repository.Repository;

/**
 * Samples. Deliberately no delete method: removal is void-marking
 * (design doc 2.0 §7 item 10). Physical deletion of withdrawn materials
 * (§7 item 8 (ii)) belongs to the later sample-API package.
 */
public interface SampleRepository extends Repository<Sample, Long> {

    Sample save(Sample sample);

    Optional<Sample> findById(Long id);

    List<Sample> findByContributorIdOrderByCreatedAtAscIdAsc(UUID contributorId);

    List<Sample> findByStatusOrderByCreatedAtAscIdAsc(SampleStatus status);
}
