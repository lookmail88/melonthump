package dev.melonthump.attest;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.fasterxml.jackson.dataformat.cbor.CBORFactory;
import java.io.ByteArrayOutputStream;
import java.io.OutputStream;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.MessageDigest;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.SecureRandom;
import java.security.Security;
import java.security.Signature;
import java.security.cert.X509Certificate;
import java.security.interfaces.ECPublicKey;
import java.security.spec.ECGenParameterSpec;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Base64;
import java.util.Date;
import org.bouncycastle.asn1.ASN1ObjectIdentifier;
import org.bouncycastle.asn1.DEROctetString;
import org.bouncycastle.asn1.x500.X500Name;
import org.bouncycastle.asn1.x509.BasicConstraints;
import org.bouncycastle.asn1.x509.Extension;
import org.bouncycastle.cert.X509CertificateHolder;
import org.bouncycastle.cert.jcajce.JcaX509CertificateConverter;
import org.bouncycastle.cert.jcajce.JcaX509v3CertificateBuilder;
import org.bouncycastle.jce.provider.BouncyCastleProvider;
import org.bouncycastle.operator.ContentSigner;
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder;

/**
 * Test double for Apple: mints a synthetic App Attest certificate chain
 * (throwaway root + intermediate) and produces attestation / assertion
 * objects with exactly the wire format and client-data convention the
 * production verifier expects. Lets the whole flow be tested without a
 * physical device or Apple's real root.
 */
public final class SyntheticAttest {

    /** Must match the default in application.properties / test profile. */
    public static final String APP_ID = "TM68JW5KDR.dev.xuyang.melonthump";
    private static final String NONCE_OID = "1.2.840.113635.100.8.2";

    private static final ObjectMapper CBOR = new ObjectMapper(new CBORFactory());
    private static final SecureRandom RANDOM = new SecureRandom();

    private static KeyPair rootKeyPair;
    private static KeyPair intermediateKeyPair;
    private static X509Certificate rootCert;
    private static X509Certificate intermediateCert;
    private static String rootCaLocation;

    private SyntheticAttest() {
    }

    /** A fake device: Secure-Enclave-style key pair plus its App Attest credential id. */
    public record Device(KeyPair keyPair, byte[] credentialId) {
        public String keyId() {
            return Base64.getEncoder().encodeToString(credentialId);
        }
    }

    public static Device newDevice() throws Exception {
        byte[] credentialId = new byte[32];
        RANDOM.nextBytes(credentialId);
        return new Device(newEcKeyPair(), credentialId);
    }

    /** Spring property value pointing at the synthetic root PEM (generated once). */
    public static synchronized String rootCaLocation() {
        ensureChain();
        return rootCaLocation;
    }

    private static synchronized void ensureChain() {
        if (rootCert != null) {
            return;
        }
        try {
            Security.addProvider(new BouncyCastleProvider());
            rootKeyPair = newEcKeyPair();
            intermediateKeyPair = newEcKeyPair();
            X500Name rootName = new X500Name("CN=Synthetic App Attest Root CA");
            X500Name intermediateName = new X500Name("CN=Synthetic App Attest Intermediate");
            rootCert = makeCert(rootName, rootKeyPair.getPublic(), rootName, rootKeyPair.getPrivate(), true, null);
            intermediateCert = makeCert(intermediateName, intermediateKeyPair.getPublic(),
                    rootName, rootKeyPair.getPrivate(), true, null);
            Path pem = Files.createTempFile("appattest-test-root", ".pem");
            try (OutputStream out = Files.newOutputStream(pem)) {
                out.write("-----BEGIN CERTIFICATE-----\n".getBytes(StandardCharsets.US_ASCII));
                out.write(Base64.getMimeEncoder(64, "\n".getBytes(StandardCharsets.US_ASCII))
                        .encodeToString(rootCert.getEncoded()).getBytes(StandardCharsets.US_ASCII));
                out.write("\n-----END CERTIFICATE-----\n".getBytes(StandardCharsets.US_ASCII));
            }
            rootCaLocation = "file:" + pem.toAbsolutePath();
        } catch (Exception e) {
            throw new IllegalStateException("cannot build synthetic attest chain", e);
        }
    }

    /** Builds a CBOR attestation object for the device over the given challenge. */
    public static byte[] attestationObject(Device device, byte[] challenge, String environment) throws Exception {
        ensureChain();
        byte[] clientDataHash = sha256(challenge);
        byte[] authData = attestationAuthData(device, environment);
        byte[] nonce = sha256(authData, clientDataHash);
        X509Certificate leaf = makeCert(new X500Name("CN=Synthetic App Attest Leaf"),
                device.keyPair().getPublic(),
                new X500Name("CN=Synthetic App Attest Intermediate"),
                intermediateKeyPair.getPrivate(), false, nonce);

        ObjectNode attStmt = CBOR.createObjectNode();
        ArrayNode x5c = attStmt.putArray("x5c");
        x5c.add(leaf.getEncoded());
        x5c.add(intermediateCert.getEncoded());
        attStmt.put("receipt", new byte[] {1, 2, 3});
        ObjectNode root = CBOR.createObjectNode();
        root.put("fmt", "apple-appattest");
        root.set("attStmt", attStmt);
        root.put("authData", authData);
        return CBOR.writeValueAsBytes(root);
    }

    /** Builds a CBOR assertion object over challenge + payload with the given sign counter. */
    public static byte[] assertionObject(Device device, byte[] challenge, byte[] payload, long signCount)
            throws Exception {
        ByteArrayOutputStream authData = new ByteArrayOutputStream();
        authData.write(sha256(APP_ID.getBytes(StandardCharsets.UTF_8)));
        authData.write(0x01); // user-present flag
        authData.write(u32(signCount));
        byte[] authDataBytes = authData.toByteArray();

        byte[] clientDataHash = sha256(challenge, sha256(payload));
        byte[] digest = sha256(authDataBytes, clientDataHash);
        Signature signer = Signature.getInstance("NONEwithECDSA");
        signer.initSign(device.keyPair().getPrivate());
        signer.update(digest);
        byte[] signature = signer.sign();

        ObjectNode root = CBOR.createObjectNode();
        root.put("signature", signature);
        root.put("authenticatorData", authDataBytes);
        return CBOR.writeValueAsBytes(root);
    }

    // ---- helpers ---------------------------------------------------------

    private static byte[] attestationAuthData(Device device, String environment) throws Exception {
        ECPublicKey pub = (ECPublicKey) device.keyPair().getPublic();
        ObjectNode cose = CBOR.createObjectNode();
        cose.put("1", 2);
        cose.put("3", -7);
        cose.put("-1", 1);
        cose.put("-2", fixed32(pub.getW().getAffineX()));
        cose.put("-3", fixed32(pub.getW().getAffineY()));
        byte[] coseBytes = CBOR.writeValueAsBytes(cose);

        ByteArrayOutputStream out = new ByteArrayOutputStream();
        out.write(sha256(APP_ID.getBytes(StandardCharsets.UTF_8)));
        out.write(0x41); // UP | AT
        out.write(u32(0));
        if ("develop".equals(environment)) {
            out.write("appattestdevelop".getBytes(StandardCharsets.US_ASCII));
        } else {
            byte[] aaguid = new byte[16];
            byte[] name = "appattest".getBytes(StandardCharsets.US_ASCII);
            System.arraycopy(name, 0, aaguid, 0, name.length);
            out.write(aaguid);
        }
        out.write((device.credentialId().length >>> 8) & 0xFF);
        out.write(device.credentialId().length & 0xFF);
        out.write(device.credentialId());
        out.write(coseBytes);
        return out.toByteArray();
    }

    private static X509Certificate makeCert(X500Name subject, PublicKey subjectKey,
                                              X500Name issuer, PrivateKey issuerKey,
                                              boolean ca, byte[] nonceExtension) throws Exception {
        Instant now = Instant.now();
        JcaX509v3CertificateBuilder builder = new JcaX509v3CertificateBuilder(
                issuer, new BigInteger(64, RANDOM).abs().add(BigInteger.ONE),
                Date.from(now.minus(1, ChronoUnit.DAYS)),
                Date.from(now.plus(365, ChronoUnit.DAYS)), subject, subjectKey);
        builder.addExtension(Extension.basicConstraints, true, new BasicConstraints(ca));
        if (nonceExtension != null) {
            builder.addExtension(new ASN1ObjectIdentifier(NONCE_OID), false,
                    new DEROctetString(nonceExtension));
        }
        ContentSigner signer = new JcaContentSignerBuilder("SHA256withECDSA")
                .setProvider("BC").build(issuerKey);
        X509CertificateHolder holder = builder.build(signer);
        return new JcaX509CertificateConverter().setProvider("BC").getCertificate(holder);
    }

    private static KeyPair newEcKeyPair() throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("EC");
        generator.initialize(new ECGenParameterSpec("secp256r1"));
        return generator.generateKeyPair();
    }

    static byte[] sha256(byte[]... parts) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        for (byte[] part : parts) {
            digest.update(part);
        }
        return digest.digest();
    }

    private static byte[] u32(long value) {
        return new byte[] {
                (byte) (value >>> 24), (byte) (value >>> 16), (byte) (value >>> 8), (byte) value};
    }

    private static byte[] fixed32(BigInteger value) {
        byte[] raw = value.toByteArray();
        byte[] out = new byte[32];
        int len = Math.min(raw.length, 32);
        System.arraycopy(raw, raw.length - len, out, 32 - len, len);
        return out;
    }
}
