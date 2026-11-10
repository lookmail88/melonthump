import dev.melonthump.api.ContributionAttestGate;
import dev.melonthump.api.ContributionAttestGate.PartDigest;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;

/** Server-side reference for the same vectors as main.swift, using the
 *  server's own ContributionAttestGate.canonicalMultipartString and the
 *  canonicalRequestString rule ("<METHOD> <URI>[?<query>]"). */
public class Check {
    static byte[] bytes(int n, int seed) {
        byte[] b = new byte[n];
        for (int i = 0; i < n; i++) b[i] = (byte) (i * 31 + seed);
        return b;
    }
    static PartDigest p(String name, byte[] data) { return new PartDigest(name, ContributionAttestGate.sha256(data)); }
    static void out(String name, String s) {
        System.out.println(name + " " + Base64.getEncoder().encodeToString(s.getBytes(StandardCharsets.UTF_8)));
    }
    static String bodiless(String method, String uri, String query) {
        // Mirrors ContributionAttestGate.canonicalRequestString(HttpServletRequest).
        return method + " " + uri + (query == null || query.isEmpty() ? "" : "?" + query);
    }
    public static void main(String[] a) {
        byte[] meta = "{\"contributorId\":\"0f8fad5b-d9cb-469f-a165-70867728950e\",\"variety\":\"KIRIN\"}"
                .getBytes(StandardCharsets.UTF_8);
        out("multipart_submit", ContributionAttestGate.canonicalMultipartString("POST", "/api/v1/contributions/samples",
                List.of(p("meta", meta), p("appearance", bytes(2000, 1)), p("appearance", bytes(1500, 2)),
                        p("recording", bytes(3000, 3)), p("cutOpen", bytes(900, 4)))));
        out("multipart_append", ContributionAttestGate.canonicalMultipartString("POST",
                "/api/v1/contributions/samples/42/parts", List.of(p("meta", meta), p("cutOpen", bytes(900, 4)))));
        out("multipart_empty_part_list", ContributionAttestGate.canonicalMultipartString("POST",
                "/api/v1/contributions/samples", new ArrayList<>()));
        out("get_status", bodiless("GET", "/api/v1/contributions/status",
                "contributorId=0f8fad5b-d9cb-469f-a165-70867728950e"));
        out("delete_sample", bodiless("DELETE", "/api/v1/contributions/samples/7",
                "contributorId=0f8fad5b-d9cb-469f-a165-70867728950e"));
        out("get_no_query", bodiless("GET", "/api/v1/contributions/samples", null));
    }
}
