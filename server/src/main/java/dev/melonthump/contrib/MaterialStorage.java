package dev.melonthump.contrib;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.UncheckedIOException;
import java.nio.file.DirectoryNotEmptyException;
import java.nio.file.FileAlreadyExistsException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.security.DigestOutputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * Server-local disk storage for contributed materials (design doc 2.0
 * §5 item 6, §7 item 8). Root: {@code melonthump.contrib.storage-dir}
 * (env {@code MELONTHUMP_CONTRIB_STORAGE_DIR}); layout
 * {@code <contributorId>/<sampleId>/<part>-<n>.<ext>}. Paths recorded in
 * {@code sample_files.stored_path} are relative to the root.
 *
 * <p>Files and database rows are kept consistent with the surrounding
 * transaction: files written inside a transaction are removed again if
 * it rolls back; deletions requested inside a transaction happen right
 * after it commits (before the HTTP response is produced), so a
 * rolled-back withdrawal never loses material.
 *
 * <p>No public endpoint serves these files.
 */
@Component
public class MaterialStorage {

    private static final Logger log = LoggerFactory.getLogger(MaterialStorage.class);

    private final Path root;

    public MaterialStorage(@Value("${melonthump.contrib.storage-dir:contrib-materials}") String storageDir) {
        this.root = Path.of(storageDir).toAbsolutePath().normalize();
        try {
            Files.createDirectories(root);
        } catch (IOException e) {
            throw new UncheckedIOException("cannot create material storage dir " + root, e);
        }
        log.info("contributed material storage at {}", root);
    }

    /** A file as written. */
    public record StoredFile(String relativePath, String sha256, long sizeBytes) {
    }

    public Path root() {
        return root;
    }

    /** Absolute location of a stored relative path (never escapes the root). */
    public Path resolve(String relativePath) {
        Path p = root.resolve(relativePath).normalize();
        if (!p.startsWith(root)) {
            throw new IllegalArgumentException("path escapes storage root");
        }
        return p;
    }

    public Path sampleDir(UUID contributorId, long sampleId) {
        return root.resolve(contributorId.toString()).resolve(Long.toString(sampleId));
    }

    /**
     * Streams {@code in} to {@code <contributorId>/<sampleId>/<part>-<n>.<ext>}
     * with the lowest free {@code n >= 1}, computing SHA-256 and size on
     * the way. Inside a transaction the file is deleted again on rollback.
     */
    public StoredFile store(UUID contributorId, long sampleId, SamplePart part, String extension, InputStream in) {
        Path dir = sampleDir(contributorId, sampleId);
        Path tmp = null;
        try {
            Files.createDirectories(dir);
            tmp = Files.createTempFile(dir, ".upload-", ".tmp");
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            long size;
            try (OutputStream out = new DigestOutputStream(
                    Files.newOutputStream(tmp, StandardOpenOption.TRUNCATE_EXISTING), digest)) {
                size = in.transferTo(out);
            }
            Path target = null;
            for (int n = nextIndex(dir, part); target == null; n++) {
                Path candidate = dir.resolve(part.fileStem() + "-" + n + "." + extension);
                try {
                    // No REPLACE_EXISTING: an existing name is never overwritten.
                    Files.move(tmp, candidate);
                    target = candidate;
                } catch (FileAlreadyExistsException taken) {
                    // try the next n
                }
            }
            tmp = null;
            deleteOnRollback(target);
            return new StoredFile(root.relativize(target).toString().replace('\\', '/'),
                    HexFormat.of().formatHex(digest.digest()), size);
        } catch (IOException e) {
            throw new UncheckedIOException("cannot store material file", e);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        } finally {
            if (tmp != null) {
                quietDelete(tmp);
            }
        }
    }

    /** 1 + the highest n already used by {@code <part>-<n>.*} in {@code dir} (any extension). */
    private static int nextIndex(Path dir, SamplePart part) throws IOException {
        String prefix = part.fileStem() + "-";
        int max = 0;
        try (var entries = Files.list(dir)) {
            for (Path p : (Iterable<Path>) entries::iterator) {
                String name = p.getFileName().toString();
                int dot = name.indexOf('.', prefix.length());
                if (name.startsWith(prefix) && dot > prefix.length()) {
                    try {
                        max = Math.max(max, Integer.parseInt(name.substring(prefix.length(), dot)));
                    } catch (NumberFormatException ignored) {
                        // not one of ours
                    }
                }
            }
        }
        return max + 1;
    }

    /**
     * Deletes the given stored files — right after the current transaction
     * commits, or immediately when there is none. With {@code sampleDir}
     * set, that directory (and the contributor directory, if it becomes
     * empty) is removed as well.
     */
    public void deleteAfterCommit(List<String> relativePaths, Path sampleDir) {
        List<Path> paths = new ArrayList<>();
        for (String rel : relativePaths) {
            paths.add(resolve(rel));
        }
        Runnable action = () -> {
            paths.forEach(MaterialStorage::quietDelete);
            if (sampleDir != null) {
                deleteDirIfEmpty(sampleDir);
                deleteDirIfEmpty(sampleDir.getParent());
            }
        };
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() {
                    action.run();
                }
            });
        } else {
            action.run();
        }
    }

    private void deleteOnRollback(Path file) {
        if (!TransactionSynchronizationManager.isSynchronizationActive()) {
            return;
        }
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCompletion(int status) {
                if (status != STATUS_COMMITTED) {
                    quietDelete(file);
                    deleteDirIfEmpty(file.getParent());
                }
            }
        });
    }

    private void deleteDirIfEmpty(Path dir) {
        if (dir == null || !dir.startsWith(root) || dir.equals(root)) {
            return;
        }
        try {
            Files.deleteIfExists(dir);
        } catch (DirectoryNotEmptyException ignored) {
            // still holds other material
        } catch (IOException e) {
            log.warn("could not remove material dir {}: {}", dir, e.getMessage());
        }
    }

    private static void quietDelete(Path p) {
        try {
            Files.deleteIfExists(p);
        } catch (IOException e) {
            log.error("could not delete material file {}: {}", p, e.getMessage());
        }
    }
}
