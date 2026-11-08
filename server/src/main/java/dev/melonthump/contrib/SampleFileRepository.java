package dev.melonthump.contrib;

import java.util.List;
import org.springframework.data.repository.Repository;

/**
 * Material file rows. Deletion exists only for contributor withdrawal
 * (§7 item 8 true deletion) and for replacing a single-file part.
 */
public interface SampleFileRepository extends Repository<SampleFile, Long> {

    SampleFile save(SampleFile file);

    List<SampleFile> findBySampleIdOrderByIdAsc(Long sampleId);

    void delete(SampleFile file);

    void flush();
}
