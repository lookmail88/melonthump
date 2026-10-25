package dev.melonthump;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * One log line per HTTP request: method, path + query, status,
 * duration, and the client's X-App-Version header when present.
 * Logged at DEBUG, and the app log level is set per environment
 * (MELONTHUMP_LOG_LEVEL: DEBUG on dev, ERROR on prod), so requests
 * are visible in the dev logs and silent in prod.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class RequestLoggingFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(RequestLoggingFilter.class);

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                    FilterChain filterChain) throws ServletException, IOException {
        long startNanos = System.nanoTime();
        try {
            filterChain.doFilter(request, response);
        } finally {
            if (log.isDebugEnabled()) {
                long millis = (System.nanoTime() - startNanos) / 1_000_000;
                String query = request.getQueryString();
                log.debug("REQ {} {}{} -> {} ({} ms) app={}",
                        request.getMethod(),
                        request.getRequestURI(),
                        query == null ? "" : "?" + query,
                        response.getStatus(),
                        millis,
                        request.getHeader("X-App-Version"));
            }
        }
    }
}
