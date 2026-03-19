#----------------------------------
# Stage 1 - Build
#----------------------------------
FROM maven:3.8.3-openjdk-17 AS builder

LABEL maintainer="Ruhon Deb <ruhondeb28@gmail.com>"

WORKDIR /app

COPY . .

RUN mvn clean package -DskipTests

#----------------------------------
# Stage 2 - Runtime
#----------------------------------
FROM eclipse-temurin:17-jre

WORKDIR /app

# Create non-root user (security)
RUN addgroup --system appgroup && adduser --system appuser --ingroup appgroup

# Copy jar
COPY --from=builder /app/target/*.jar app.jar

# Switch to non-root user
USER appuser

# Expose port
EXPOSE 8080

# JVM tuning (production)
ENTRYPOINT ["java", "-Xms256m", "-Xmx512m", "-jar", "app.jar"]