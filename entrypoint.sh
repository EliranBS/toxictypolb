#!/bin/sh
set -e

# Start the Spring Boot application as PID 1 so container signals are handled correctly.
# JAVA_OPTS can be supplied at runtime for memory, garbage collection, or JVM tuning options.
exec java ${JAVA_OPTS:-} -jar /app/app.jar "$@"
