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
    private String variantColor = "#3B82F6";
    private String customerName = "Harness Customer";
    private String customerLogo = "";
    private String deploymentTarget = "kubernetes";
    private String podName = "local";
    private String namespace = "default";
    private String region = "us-east-1";
    private boolean chaosEnabled = true;
    private int chaosLatencyMs = 0;
    private double chaosErrorRate = 0.0;
}
