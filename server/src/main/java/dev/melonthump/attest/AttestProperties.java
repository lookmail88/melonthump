package dev.melonthump.attest;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/** App Attest configuration (design doc §5/§7). */
@Component
public class AttestProperties {

    private final String appId;
    private final boolean acceptDevelop;
    private final boolean debugBypassEnabled;
    private final int challengeTtlSeconds;
    private final String rootCaLocation;

    public AttestProperties(
            @Value("${melonthump.attest.app-id}") String appId,
            @Value("${melonthump.attest.accept-develop:false}") boolean acceptDevelop,
            @Value("${melonthump.attest.debug-bypass-enabled:false}") boolean debugBypassEnabled,
            @Value("${melonthump.attest.challenge-ttl-seconds:300}") int challengeTtlSeconds,
            @Value("${melonthump.attest.root-ca-location}") String rootCaLocation) {
        this.appId = appId;
        this.acceptDevelop = acceptDevelop;
        this.debugBypassEnabled = debugBypassEnabled;
        this.challengeTtlSeconds = challengeTtlSeconds;
        this.rootCaLocation = rootCaLocation;
    }

    /** App ID as Apple defines it: "<TeamID>.<bundleID>". Its SHA-256 is the RP ID hash. */
    public String appId() {
        return appId;
    }

    /** Whether develop-environment attestations are accepted (dev backend only). */
    public boolean acceptDevelop() {
        return acceptDevelop;
    }

    /** Simulator debug bypass header is honoured only when true (dev manifest only). */
    public boolean debugBypassEnabled() {
        return debugBypassEnabled;
    }

    public int challengeTtlSeconds() {
        return challengeTtlSeconds;
    }

    /** Spring resource location of the App Attest root CA PEM (bundled; tests may override). */
    public String rootCaLocation() {
        return rootCaLocation;
    }
}
