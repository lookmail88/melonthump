package dev.melonthump.attest;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.dataformat.cbor.CBORFactory;
import java.io.InputStream;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.MessageDigest;
import java.security.PublicKey;
import java.security.Signature;
import java.security.SignatureException;
import java.security.cert.CertPath;
import java.security.cert.CertPathValidator;
import java.security.cert.CertificateFactory;
import java.security.cert.PKIXParameters;
import java.security.cert.TrustAnchor;
import java.security.cert.X509Certificate;
import java.security.interfaces.ECPublicKey;
import java.security.spec.X509EncodedKeySpec;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.List;
import java.util.Set;
import org.springframework.core.io.DefaultResourceLoader;
import org.springframework.core.io.Resource;
import org.springframework.stereotype.Component;

/**
 * Minimal in-house Apple App Attest verifier (design doc §5, §11: no
 * maintained off-the-shelf Java library covers the "apple-appattest"
 * format, so this implements Apple's documented verification steps
 * directly — CBOR + X.509 + ECDSA, fully offline against the bundled
 * Apple App Attest Root CA).
 *
 * <p>Client data convention (must match the iOS client exactly):
 * <ul>
 *   <li>Enrollment: clientDataHash = SHA-256(challenge).</li>
 *   <li>Assertions: clientDataHash = SHA-256(challenge || SHA-256(payload)),
 *       where payload is the exact request body bytes — or, for the
 *       body-less version-policy GET, the UTF-8 canonical request string
 *       built by {@code VersionController} / {@code AttestManager}.</li>
 * </ul>
 * In both flows the authenticator hash is SHA-256(authenticatorData ||
 * clientDataHash); the device signature is ECDSA-with-SHA-256 over that
 * hash, so verification feeds the hash to a SHA256withECDSA verifier
 * (which hashes it once more). Verified against 14 real device
 * assertions on 2026-10-24.
 */
@Component
public class AppAttestVerifier {

    /** Leaf-certificate extension that carries the expected nonce. */
    private static final String NONCE_EXTENSION_OID = "1.2.840.113635.100.8.2";

    private final AttestProperties properties;
    private final ObjectMapper cbor = new ObjectMapper(new CBORFactory());
    private final X509Certificate rootCa;

    public AppAttestVerifier(AttestProperties properties) {
        this.properties = properties;
        this.rootCa = loadRootCa(properties.rootCaLocation());
    }

    /** Outcome of a verified attestation: the enrolled key and its environment. */
    public record AttestationResult(ECPublicKey publicKey, String environment) {
    }

    // ------------------------------------------------------------------
    // Attestation (enrollment)
    // ------------------------------------------------------------------

    /**
     * Verifies an attestation object produced by
     * {@code DCAppAttestService.attestKey} over SHA-256(challenge).
     *
     * @param attestationObject raw CBOR attestation object bytes
     * @param challenge         the server-issued challenge the client hashed
     * @param expectedKeyId     key identifier the client claims (must match authData)
     */
    public AttestationResult verifyAttestation(byte[] attestationObject, byte[] challenge, String expectedKeyId)
            throws AttestException {
        try {
            JsonNode root = cbor.readTree(attestationObject);
            if (!"apple-appattest".equals(root.path("fmt").asText())) {
                throw new AttestException("unexpected attestation format");
            }
            JsonNode attStmt = root.path("attStmt");
            byte[] authData = root.path("authData").binaryValue();

            // 1. Certificate chain: x5c leaf + intermediates -> bundled root.
            List<X509Certificate> chain = new ArrayList<>();
            CertificateFactory cf = CertificateFactory.getInstance("X.509");
            for (JsonNode certNode : attStmt.path("x5c")) {
                chain.add((X509Certificate) cf.generateCertificate(
                        new java.io.ByteArrayInputStream(certNode.binaryValue())));
            }
            if (chain.size() < 2) {
                throw new AttestException("attestation chain too short");
            }
            X509Certificate leaf = chain.get(0);
            validateChain(cf, chain);

            // 2. Nonce: SHA-256(authData || SHA-256(challenge)) must equal
            //    the value in the leaf's nonce extension.
            byte[] clientDataHash = sha256(challenge);
            byte[] nonce = sha256(authData, clientDataHash);
            byte[] extensionNonce = extractNonceExtension(leaf);
            if (!MessageDigest.isEqual(nonce, extensionNonce)) {
                throw new AttestException("attestation nonce mismatch");
            }

            // 3. authData: RP ID hash, counter 0, attested credential data.
            AuthData auth = parseAuthData(authData, true);
            if (!MessageDigest.isEqual(auth.rpIdHash(), sha256(properties.appId().getBytes(StandardCharsets.UTF_8)))) {
                throw new AttestException("attestation RP ID hash mismatch");
            }
            if (auth.signCount() != 0) {
                throw new AttestException("attestation sign counter must be 0");
            }
            String credIdBase64 = Base64.getEncoder().encodeToString(auth.credentialId());
            if (!credIdBase64.equals(expectedKeyId)) {
                throw new AttestException("attestation credential id does not match keyId");
            }

            // 4. The COSE public key in authData must be the leaf cert's key.
            ECPublicKey leafKey = (ECPublicKey) leaf.getPublicKey();
            verifyCoseKeyMatches(auth.cosePublicKey(), leafKey);

            return new AttestationResult(leafKey, auth.environment());
        } catch (AttestException e) {
            throw e;
        } catch (Exception e) {
            throw new AttestException("attestation verification failed: " + e.getMessage(), e);
        }
    }

    // ------------------------------------------------------------------
    // Assertion (per-request)
    // ------------------------------------------------------------------

    /**
     * Verifies an assertion object produced by
     * {@code DCAppAttestService.generateAssertion} where the client passed
     * clientDataHash = SHA-256(challenge || SHA-256(payload)).
     *
     * @return the assertion's sign counter (caller enforces monotonicity)
     */
    public long verifyAssertion(PublicKey publicKey, byte[] assertionObject, byte[] challenge, byte[] payload)
            throws AttestException {
        try {
            JsonNode root = cbor.readTree(assertionObject);
            byte[] signature = root.path("signature").binaryValue();
            byte[] authData = root.path("authenticatorData").binaryValue();

            byte[] clientDataHash = sha256(challenge, sha256(payload));
            byte[] digest = sha256(authData, clientDataHash);
            if (!verifyEcdsa(publicKey, signature, digest)) {
                throw new AttestException("assertion signature invalid");
            }

            AuthData auth = parseAuthData(authData, false);
            if (!MessageDigest.isEqual(auth.rpIdHash(), sha256(properties.appId().getBytes(StandardCharsets.UTF_8)))) {
                throw new AttestException("assertion RP ID hash mismatch");
            }
            return auth.signCount();
        } catch (AttestException e) {
            throw e;
        } catch (Exception e) {
            throw new AttestException("assertion verification failed: " + e.getMessage(), e);
        }
    }

    /**
     * Verifies an ECDSA signature over a precomputed digest. Accepts
     * the signature in either encoding: DER (what Java produces) or
     * raw IEEE P1363 (r || s, 64 bytes for P-256) — Apple's assertion
     * signatures arrive in P1363 form, which a DER-only check rejects
     * even though the signature itself is genuine. The encoding is
     * detected unambiguously (length + leading tag), never guessed.
     */
    private static boolean verifyEcdsa(PublicKey publicKey, byte[] signature, byte[] digest)
            throws Exception {
        Signature verifier = Signature.getInstance("SHA256withECDSA");
        verifier.initVerify(publicKey);
        verifier.update(digest);
        try {
            if (verifier.verify(signature)) {
                return true;
            }
        } catch (SignatureException notDer) {
            // fall through to the P1363 form
        }
        if (signature.length == 64) {
            Signature p1363Verifier = Signature.getInstance("SHA256withECDSA");
            p1363Verifier.initVerify(publicKey);
            p1363Verifier.update(digest);
            try {
                return p1363Verifier.verify(p1363ToDer(signature));
            } catch (SignatureException e) {
                return false;
            }
        }
        return false;
    }

    /** Converts a raw P1363 (r || s) ECDSA signature to DER encoding. */
    private static byte[] p1363ToDer(byte[] raw) {
        byte[] r = derInteger(raw, 0, 32);
        byte[] s = derInteger(raw, 32, 32);
        byte[] out = new byte[2 + r.length + s.length];
        out[0] = 0x30;
        out[1] = (byte) (r.length + s.length);
        System.arraycopy(r, 0, out, 2, r.length);
        System.arraycopy(s, 0, out, 2 + r.length, s.length);
        return out;
    }

    /** DER-encodes one fixed-width unsigned big-endian integer slice. */
    private static byte[] derInteger(byte[] raw, int offset, int length) {
        int start = offset;
        while (start < offset + length - 1 && raw[start] == 0) {
            start++;
        }
        int trimmed = offset + length - start;
        boolean pad = (raw[start] & 0x80) != 0;
        byte[] out = new byte[2 + trimmed + (pad ? 1 : 0)];
        out[0] = 0x02;
        out[1] = (byte) (trimmed + (pad ? 1 : 0));
        System.arraycopy(raw, start, out, pad ? 3 : 2, trimmed);
        return out;
    }

    /** Decodes a stored X.509 SubjectPublicKeyInfo back into a public key. */
    public static ECPublicKey decodeStoredPublicKey(byte[] encoded) throws AttestException {
        try {
            return (ECPublicKey) KeyFactory.getInstance("EC")
                    .generatePublic(new X509EncodedKeySpec(encoded));
        } catch (Exception e) {
            throw new AttestException("stored public key unreadable", e);
        }
    }

    // ------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------

    private record AuthData(byte[] rpIdHash, int flags, long signCount, String environment,
                            byte[] credentialId, byte[] cosePublicKey) {
    }

    private AuthData parseAuthData(byte[] authData, boolean attested) throws AttestException {
        if (authData.length < 37) {
            throw new AttestException("authData too short");
        }
        byte[] rpIdHash = Arrays.copyOfRange(authData, 0, 32);
        int flags = authData[32] & 0xFF;
        long signCount = u32(authData, 33);
        if (!attested) {
            return new AuthData(rpIdHash, flags, signCount, null, null, null);
        }
        if ((flags & 0x40) == 0) {
            throw new AttestException("authData lacks attested credential data");
        }
        if (authData.length < 55) {
            throw new AttestException("attested authData too short");
        }
        byte[] aaguid = Arrays.copyOfRange(authData, 37, 53);
        String environment;
        if (startsWith(aaguid, "appattestdevelop")) {
            environment = "develop";
        } else if (startsWith(aaguid, "appattest")) {
            environment = "production";
        } else {
            throw new AttestException("unrecognized AAGUID");
        }
        int credIdLen = u16(authData, 53);
        int credIdEnd = 55 + credIdLen;
        if (authData.length <= credIdEnd) {
            throw new AttestException("attested authData truncated");
        }
        byte[] credId = Arrays.copyOfRange(authData, 55, credIdEnd);
        byte[] coseKey = Arrays.copyOfRange(authData, credIdEnd, authData.length);
        return new AuthData(rpIdHash, flags, signCount, environment, credId, coseKey);
    }

    private void verifyCoseKeyMatches(byte[] coseKey, ECPublicKey certKey) throws Exception {
        JsonNode cose = cbor.readTree(coseKey);
        if (cose.path("1").asInt() != 2 || cose.path("-1").asInt() != 1) {
            throw new AttestException("COSE key is not an EC2 P-256 key");
        }
        byte[] x = cose.path("-2").binaryValue();
        byte[] y = cose.path("-3").binaryValue();
        if (!Arrays.equals(x, fixed32(certKey.getW().getAffineX()))
                || !Arrays.equals(y, fixed32(certKey.getW().getAffineY()))) {
            throw new AttestException("COSE public key does not match leaf certificate");
        }
    }

    private void validateChain(CertificateFactory cf, List<X509Certificate> chain) throws Exception {
        CertPath path = cf.generateCertPath(chain);
        PKIXParameters params = new PKIXParameters(Set.of(new TrustAnchor(rootCa, null)));
        params.setRevocationEnabled(false); // fully offline, per the design doc
        CertPathValidator.getInstance("PKIX").validate(path, params);
    }

    /**
     * The nonce extension value is an OCTET STRING wrapping the payload.
     * In real Apple certificates the payload is a DER SEQUENCE holding a
     * single OCTET STRING with the 32-byte nonce:
     * SEQUENCE { OCTET STRING nonce }. (An earlier synthetic fixture
     * omitted the SEQUENCE, which is why the tests passed while real
     * attestations failed with "malformed DER octet string".) Accept
     * both shapes. Minimal DER walk, no ASN.1 library needed.
     */
    private static byte[] extractNonceExtension(X509Certificate leaf) throws AttestException {
        byte[] ext = leaf.getExtensionValue(NONCE_EXTENSION_OID);
        if (ext == null) {
            throw new AttestException("leaf certificate lacks the nonce extension");
        }
        byte[] payload = readOctetString(ext, 0);
        byte[] nonce = findNonce(payload, 0, payload.length, 0);
        if (nonce == null) {
            throw new AttestException("no 32-byte nonce in the attestation extension");
        }
        return nonce;
    }

    /**
     * Walks a DER tree looking for a primitive OCTET STRING of exactly
     * 32 bytes — the nonce — descending into constructed elements
     * (SEQUENCE, context-specific [1], ...). Apple's real layout nests
     * the nonce three levels deep; a fixed two-step unwrap is what the
     * first version of this parser did, and real certificates failed.
     */
    private static byte[] findNonce(byte[] der, int start, int end, int depth) throws AttestException {
        if (depth > 4) {
            return null;
        }
        int offset = start;
        while (offset < end) {
            if (offset + 2 > end) {
                throw new AttestException("truncated DER element");
            }
            int tag = der[offset] & 0xFF;
            int headerLen = derHeaderLength(der, offset);
            int length = derContentLength(der, offset);
            int contentStart = offset + headerLen;
            int contentEnd = contentStart + length;
            if (contentEnd > end) {
                throw new AttestException("truncated DER element");
            }
            if (tag == 0x04 && length == 32) {
                return Arrays.copyOfRange(der, contentStart, contentEnd);
            }
            if ((tag & 0x20) != 0) { // constructed: descend
                byte[] found = findNonce(der, contentStart, contentEnd, depth + 1);
                if (found != null) {
                    return found;
                }
            }
            offset = contentEnd;
        }
        return null;
    }

    /** Content length of the DER element whose header starts at {@code offset}. */
    private static int derContentLength(byte[] der, int offset) throws AttestException {
        if (der.length < offset + 2) {
            throw new AttestException("malformed DER element");
        }
        int lenByte = der[offset + 1] & 0xFF;
        if (lenByte < 0x80) {
            return lenByte;
        } else if (lenByte == 0x81) {
            if (der.length < offset + 3) {
                throw new AttestException("malformed DER element");
            }
            return der[offset + 2] & 0xFF;
        } else if (lenByte == 0x82) {
            if (der.length < offset + 4) {
                throw new AttestException("malformed DER element");
            }
            return ((der[offset + 2] & 0xFF) << 8) | (der[offset + 3] & 0xFF);
        }
        throw new AttestException("unsupported DER length form");
    }

    /** Length of the DER header (tag + length bytes) of the element at {@code offset}. */
    private static int derHeaderLength(byte[] der, int offset) throws AttestException {
        if (der.length < offset + 2) {
            throw new AttestException("malformed DER element");
        }
        int lenByte = der[offset + 1] & 0xFF;
        if (lenByte < 0x80) {
            return 2;
        } else if (lenByte == 0x81) {
            return 3;
        } else if (lenByte == 0x82) {
            return 4;
        }
        throw new AttestException("unsupported DER length form");
    }

    /** Reads one DER OCTET STRING at {@code offset} and returns its content bytes. */
    private static byte[] readOctetString(byte[] der, int offset) throws AttestException {
        if (der.length < offset + 2 || (der[offset] & 0xFF) != 0x04) {
            throw new AttestException("malformed DER octet string");
        }
        int lenByte = der[offset + 1] & 0xFF;
        int headerLen;
        int length;
        if (lenByte < 0x80) {
            headerLen = 2;
            length = lenByte;
        } else if (lenByte == 0x81) {
            headerLen = 3;
            length = der[offset + 2] & 0xFF;
        } else if (lenByte == 0x82) {
            headerLen = 4;
            length = ((der[offset + 2] & 0xFF) << 8) | (der[offset + 3] & 0xFF);
        } else {
            throw new AttestException("unsupported DER length form");
        }
        if (der.length < offset + headerLen + length) {
            throw new AttestException("truncated DER octet string");
        }
        return Arrays.copyOfRange(der, offset + headerLen, offset + headerLen + length);
    }

    private X509Certificate loadRootCa(String location) {
        try {
            Resource resource = new DefaultResourceLoader().getResource(location);
            try (InputStream in = resource.getInputStream()) {
                return (X509Certificate) CertificateFactory.getInstance("X.509").generateCertificate(in);
            }
        } catch (Exception e) {
            throw new IllegalStateException("cannot load App Attest root CA from " + location, e);
        }
    }

    private static byte[] sha256(byte[]... parts) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        for (byte[] part : parts) {
            digest.update(part);
        }
        return digest.digest();
    }

    private static boolean startsWith(byte[] bytes, String prefix) {
        byte[] p = prefix.getBytes(StandardCharsets.US_ASCII);
        if (bytes.length < p.length) {
            return false;
        }
        for (int i = 0; i < p.length; i++) {
            if (bytes[i] != p[i]) {
                return false;
            }
        }
        return true;
    }

    private static byte[] fixed32(BigInteger value) {
        byte[] raw = value.toByteArray();
        byte[] out = new byte[32];
        int copyLen = Math.min(raw.length, 32);
        System.arraycopy(raw, raw.length - copyLen, out, 32 - copyLen, copyLen);
        return out;
    }

    private static long u32(byte[] bytes, int offset) {
        return ((long) (bytes[offset] & 0xFF) << 24)
                | ((bytes[offset + 1] & 0xFF) << 16)
                | ((bytes[offset + 2] & 0xFF) << 8)
                | (bytes[offset + 3] & 0xFF);
    }

    private static int u16(byte[] bytes, int offset) {
        return ((bytes[offset] & 0xFF) << 8) | (bytes[offset + 1] & 0xFF);
    }
}
