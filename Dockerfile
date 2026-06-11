
FROM alpine:latest AS agent-downloader
RUN apk add --no-cache curl
RUN curl -L https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/latest/download/opentelemetry-javaagent.jar -o /opentelemetry-javaagent.jar

FROM maven:3.8.3-openjdk-17 AS builder
WORKDIR /app
COPY . .
RUN mvn clean package -DskipTests -Dmaven.wagon.http.retryHandler.count=3

FROM eclipse-temurin:17-jre

LABEL maintainer="Rohan Dev <rohan@rohandevops.co.in>"
WORKDIR /app
RUN addgroup --system appgroup && adduser --system appuser --ingroup appgroup

COPY --from=agent-downloader /opentelemetry-javaagent.jar /app/opentelemetry-javaagent.jar

COPY --from=builder /app/target/*.jar app.jar

RUN chown appuser:appgroup /app/app.jar /app/opentelemetry-javaagent.jar

USER appuser
EXPOSE 8080

ENTRYPOINT ["java", "-Xms256m", "-Xmx512m", "-javaagent:/app/opentelemetry-javaagent.jar", "-jar", "app.jar"]