#----------------------------------
# Stage 1 - Agent Downloader (Security & Lean Build)
#----------------------------------
FROM alpine:latest AS agent-downloader
RUN apk add --no-cache curl
# Download the latest stable OpenTelemetry Java Agent
RUN curl -L https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/latest/download/opentelemetry-javaagent.jar \
    -o /opentelemetry-javaagent.jar

#----------------------------------
# Stage 2 - Application Build
#----------------------------------
FROM maven:3.8.3-openjdk-17 AS builder
WORKDIR /app
COPY . .
RUN mvn clean package -DskipTests -Dmaven.wagon.http.retryHandler.count=3

#----------------------------------
# Stage 3 - Final Production Runtime
#----------------------------------
FROM eclipse-temurin:17-jre

LABEL maintainer="Rohan Dev <rohan@rohandevops.co.in>"
WORKDIR /app

# 1. Create non-root user (Standard Security)
RUN addgroup --system appgroup && adduser --system appuser --ingroup appgroup

# 2. Copy the OTel Agent from Stage 1
COPY --from=agent-downloader /opentelemetry-javaagent.jar /app/opentelemetry-javaagent.jar

# 3. Copy the Banking JAR from Stage 2
COPY --from=builder /app/target/*.jar app.jar

# 4. Set correct ownership (Crucial for non-root execution)
RUN chown appuser:appgroup /app/app.jar /app/opentelemetry-javaagent.jar

USER appuser
EXPOSE 8080

# 5. JVM Tuning + OTel Integration
# We use exec form to ensure signals (SIGTERM) are passed to the JVM for graceful shutdown
ENTRYPOINT ["java", "-Xms256m", "-Xmx512m", "-javaagent:/app/opentelemetry-javaagent.jar", "-jar", "app.jar"]