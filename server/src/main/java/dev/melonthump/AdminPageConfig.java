package dev.melonthump;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.filter.OncePerRequestFilter;
import org.springframework.web.servlet.config.annotation.ViewControllerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * The owner admin web page (design doc 2.0 §2 item 7, §7 item 11; S4):
 * static, framework-free assets under {@code classpath:/static/admin/},
 * served at {@code /admin/}. The page holds no data and no credentials —
 * it is a pure client of {@code /api/admin/**} — so it is served whether
 * or not {@code melonthump.admin.enabled} is on; with the flag off its API
 * calls 404 and the page shows an "admin API disabled" state. In
 * production Cloudflare Access fronts {@code /admin/} as well as the API.
 *
 * <p>Every {@code /admin/} response carries a strict same-origin Content
 * Security Policy (no remote resources, no inline script or style) and is
 * not cached, so a redeploy is picked up on the next load.
 */
@Configuration
public class AdminPageConfig implements WebMvcConfigurer {

    static final String CSP = "default-src 'none'; script-src 'self'; style-src 'self'; "
            + "img-src 'self' data:; media-src 'self'; connect-src 'self'; base-uri 'none'; "
            + "form-action 'none'; frame-ancestors 'none'";

    @Override
    public void addViewControllers(ViewControllerRegistry registry) {
        registry.addRedirectViewController("/admin", "/admin/");
        registry.addViewController("/admin/").setViewName("forward:/admin/index.html");
    }

    @Bean
    FilterRegistrationBean<OncePerRequestFilter> adminPageHeaders() {
        FilterRegistrationBean<OncePerRequestFilter> reg = new FilterRegistrationBean<>(new OncePerRequestFilter() {
            @Override
            protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                            FilterChain chain) throws ServletException, IOException {
                response.setHeader("Content-Security-Policy", CSP);
                response.setHeader("X-Content-Type-Options", "nosniff");
                response.setHeader("Referrer-Policy", "no-referrer");
                response.setHeader("X-Frame-Options", "DENY");
                response.setHeader("Cache-Control", "no-cache");
                chain.doFilter(request, response);
            }
        });
        reg.addUrlPatterns("/admin", "/admin/*");
        reg.setName("adminPageHeaders");
        return reg;
    }
}
