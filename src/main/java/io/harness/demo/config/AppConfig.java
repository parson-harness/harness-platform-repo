package io.harness.demo.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

@Data
@Configuration
@ConfigurationProperties(prefix = "app")
public class AppConfig {
    private static final Pattern SEMVER_PATTERN = Pattern.compile("^\\d+\\.\\d+\\.\\d+$");
    private static final Pattern ASG_BUILD_VERSION_PATTERN = Pattern.compile("^(?:.*-)?(\\d+)(?:-[A-Za-z0-9]+)?$");
    
    private String appName = "My Application";
    private String version = "1.0.0";
    private String buildId = "";
    private String environment = "development";
    private String deploymentVariant = "";
    private String deploymentTrack = "";
    private String deploymentStrategy = "";
    private String customerName = "Harness Customer";
    private String customerLogo = "";
    private String deploymentTarget = "kubernetes";
    private String publicUrl = "";
    private String stageUrl = "";
    private String podName = "local";
    private String namespace = "default";
    private String region = "us-east-1";
    private boolean chaosEnabled = true;
    private int chaosLatencyMs = 0;
    private double chaosErrorRate = 0.0;
    
    /**
     * Returns the effective deployment variant for display.
     * Blue/Green deployments use harness.io/color label (blue/green).
     * Canary deployments use harness.io/track label (canary/stable).
     * This method returns the appropriate value based on what's set.
     */
    public String getEffectiveVariant() {
        // If color is set (blue/green deployment), use it
        if (deploymentVariant != null && !deploymentVariant.isEmpty()) {
            return deploymentVariant;
        }
        // Otherwise use track (canary deployment)
        if (deploymentTrack != null && !deploymentTrack.isEmpty()) {
            return deploymentTrack;
        }
        return "stable";
    }

    public String getDisplayVersion() {
        if (version == null || version.isBlank()) {
            return "1.0.0";
        }
        String trimmed = version.trim();
        if (SEMVER_PATTERN.matcher(trimmed).matches()) {
            return trimmed;
        }
        Matcher matcher = ASG_BUILD_VERSION_PATTERN.matcher(trimmed);
        if (matcher.matches()) {
            return "1.0." + matcher.group(1);
        }
        return trimmed;
    }
    
    public String getVariantColor() {
        String variant = getEffectiveVariant();
        if (variant == null) {
            return "#8B5CF6"; // Purple for stable/unknown
        }
        switch (variant.toLowerCase()) {
            case "blue":
                return "#3B82F6"; // Blue
            case "green":
                return "#22C55E"; // Green
            case "canary":
                return "#EAB308"; // Yellow/Amber
            case "stable":
            default:
                return "#8B5CF6"; // Purple for stable
        }
    }
}
