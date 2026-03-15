# Build stage
FROM maven:3.9-eclipse-temurin-17-alpine AS build
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -B
COPY src ./src
RUN mvn package -DskipTests -B

# Runtime stage
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app

# Add non-root user for security
RUN addgroup -g 1001 appgroup && \
    adduser -u 1001 -G appgroup -D appuser

# Copy the jar
COPY --from=build /app/target/*.jar app.jar

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
    CMD wget -q --spider http://localhost:8080/actuator/health || exit 1

ENTRYPOINT ["java", "-jar", "app.jar"]
