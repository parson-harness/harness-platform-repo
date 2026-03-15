# Build stage
FROM eclipse-temurin:17-jre
WORKDIR /app

# Install curl for healthcheck
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Add non-root user for security
RUN groupadd -g 1001 appgroup && \
    useradd -u 1001 -g appgroup -m appuser

# Copy the pre-built jar (built locally with mvn package)
COPY --chown=appuser:appgroup target/*.jar app.jar

# Set ownership
RUN chown -R appuser:appgroup /app

USER appuser

# Default environment variables
ENV APP_VERSION=1.0.0 \
    APP_ENVIRONMENT=production \
    DEPLOYMENT_VARIANT=stable \
    VARIANT_COLOR=#3B82F6 \
    CUSTOMER_NAME="Harness Customer" \
    CHAOS_ENABLED=true \
    CHAOS_LATENCY_MS=0 \
    CHAOS_ERROR_RATE=0.0

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8080/actuator/health || exit 1

ENTRYPOINT ["java", "-jar", "app.jar"]
