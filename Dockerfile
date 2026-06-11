# Build the Spring Boot application with Maven and Java 8.
FROM maven:3.6.3-jdk-8 AS build

WORKDIR /workspace

# Copy Maven wrapper and project metadata first to improve Docker layer reuse.
COPY .mvn/ .mvn/
COPY mvnw pom.xml ./

# Copy the application source and tests, then build the executable Spring Boot jar.
COPY src/ src/
RUN chmod +x ./mvnw && ./mvnw -B verify

# Run the application from a small Java 8 runtime image.
FROM amazoncorretto:8-alpine-jre

WORKDIR /app

# Copy only the generated application jar from the build stage.
COPY --from=build /workspace/target/*.jar /app/app.jar
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/app/entrypoint.sh"]
