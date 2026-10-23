# Build stage
FROM maven:3.9-eclipse-temurin-25 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn -q dependency:go-offline
COPY src ./src
RUN mvn -q clean package -DskipTests

# Runtime stage
FROM eclipse-temurin:25-jre
WORKDIR /app
# Client version policy: CI stamps the iOS app's MARKETING_VERSION here
# (workflow build-arg); phones read it via /api/v1/version/getclientversion.
ARG CLIENT_LATEST_VERSION=1.0.0
ENV MELONTHUMP_CLIENT_LATEST_VERSION=$CLIENT_LATEST_VERSION
COPY --from=build /app/target/melonthump-server-*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
