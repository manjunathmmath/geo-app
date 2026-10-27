# Build stage: compile and package the API with Maven (the tests need Docker, so they run in CI/locally, not here).
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /src
COPY pom.xml .
RUN mvn -q -B dependency:go-offline
COPY src ./src
RUN mvn -q -B -DskipTests package

# Run stage: a JRE, ffmpeg (preview images of photos and videos) and the jar, as a non-root user.
FROM eclipse-temurin:21-jre
RUN apt-get update \
 && apt-get install -y --no-install-recommends ffmpeg \
 && rm -rf /var/lib/apt/lists/*
RUN useradd --system --uid 10001 --no-create-home app \
 && mkdir -p /data/uploads && chown app /data/uploads
WORKDIR /app
COPY --from=build /src/target/*.jar app.jar
USER app
EXPOSE 8080
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=70", "-jar", "app.jar"]
