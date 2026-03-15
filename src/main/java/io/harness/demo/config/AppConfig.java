package io.harness.demo.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;

@Data
@Configuration
@ConfigurationProperties(prefix = "app")
public class AppConfig {
    
    private String appName = "My Application";
    private String version = "1.0.0";
    private String environment = "development";
    private String deploymentVariant = "stable";
    private String customerName = "Harness Customer";
    private String customerLogo = "";
    private String deploymentTarget = "kubernetes";
    private String podName = "local";
    private String namespace = "default";
    private String region = "us-east-1";
    private boolean chaosEnabled = true;
    private int chaosLatencyMs = 0;
    private double chaosErrorRate = 0.0;
    
    public String getVariantColor() {
        if (deploymentVariant == null) {
            return "#8B5CF6"; // Purple for stable/unknown
        }
        switch (deploymentVariant.toLowerCase()) {
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
