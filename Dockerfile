# Used by Jenkins to build a runnable image for ZAP scanning

# This Dockerfile is used to create a Docker image that contains the Spring Petclinic application built with Gradle.
FROM eclipse-temurin:17-jre-alpine

# Set the working directory inside the container
WORKDIR /app

# Label the image with the author's name
LABEL authors="baezecillo"

# Create a non-root user and group for running the application
ARG USER=petclinic
ARG UID=1000
RUN addgroup -S $USER && adduser -S -u $UID -G $USER $USER

# Copy the Gradle-built JAR and transfer ownership to the app user
COPY build/libs/*.jar app.jar
RUN chown $USER:$USER app.jar

USER $USER

# Expose the default Spring Boot port
EXPOSE 8080

# Set the entry point to run the Spring Boot application
ENTRYPOINT ["java", "-jar", "app.jar"]
