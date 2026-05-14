#!/bin/bash
# Auto-generates a Dockerfile when the app repo has none.
# Called from cloudpilot-deploy.yml inside the app_source directory.
set -euo pipefail

DOCKERFILE_CONTEXT="."
DOCKERFILE_PATH="Dockerfile"

if [ -f "package.json" ]; then
  START_CMD=$(node -e "try{const p=require('./package.json');console.log(p.scripts&&p.scripts.start?'npm start':'node index.js')}catch(e){console.log('npm start')}" 2>/dev/null || echo "npm start")
  BUILD_CMD=""
  if node -e "const p=require('./package.json');process.exit(p.scripts&&p.scripts.build?0:1)" 2>/dev/null; then
    BUILD_CMD="RUN npm run build"
  fi
  cat > Dockerfile <<DEOF
FROM node:20-slim
WORKDIR /app
COPY package*.json ./
RUN npm install --omit=dev
COPY . .
${BUILD_CMD}
EXPOSE 3000
CMD ["sh","-c","${START_CMD}"]
DEOF
  echo "DOCKERFILE_PATH=Dockerfile" >> "$GITHUB_ENV"
  echo "DOCKERFILE_CONTEXT=." >> "$GITHUB_ENV"
  echo "Generated Node.js Dockerfile"

elif [ -f "pom.xml" ]; then
  cat > Dockerfile <<DEOF
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -q
COPY src ./src
RUN mvn package -DskipTests -q

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java","-jar","app.jar"]
DEOF
  echo "DOCKERFILE_PATH=Dockerfile" >> "$GITHUB_ENV"
  echo "DOCKERFILE_CONTEXT=." >> "$GITHUB_ENV"
  echo "Generated Maven/Java Dockerfile"

elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
  cat > Dockerfile <<DEOF
FROM gradle:8-jdk21 AS build
WORKDIR /app
COPY . .
RUN gradle bootJar --no-daemon -q

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=build /app/build/libs/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java","-jar","app.jar"]
DEOF
  echo "DOCKERFILE_PATH=Dockerfile" >> "$GITHUB_ENV"
  echo "DOCKERFILE_CONTEXT=." >> "$GITHUB_ENV"
  echo "Generated Gradle/Java Dockerfile"

elif [ -f "requirements.txt" ] || [ -f "pyproject.toml" ]; then
  DEPS_CMD="pip install -r requirements.txt"
  [ -f "pyproject.toml" ] && DEPS_CMD="pip install ."
  cat > Dockerfile <<DEOF
FROM python:3.12-slim
WORKDIR /app
COPY . .
RUN ${DEPS_CMD}
EXPOSE 8000
CMD ["python", "app.py"]
DEOF
  echo "DOCKERFILE_PATH=Dockerfile" >> "$GITHUB_ENV"
  echo "DOCKERFILE_CONTEXT=." >> "$GITHUB_ENV"
  echo "Generated Python Dockerfile"

elif [ -f "go.mod" ]; then
  APP_NAME=$(head -1 go.mod | awk '{print $2}' | xargs basename)
  cat > Dockerfile <<DEOF
FROM golang:1.22-alpine AS build
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o /app/server .

FROM alpine:3.19
WORKDIR /app
COPY --from=build /app/server .
EXPOSE 8080
CMD ["/app/server"]
DEOF
  echo "DOCKERFILE_PATH=Dockerfile" >> "$GITHUB_ENV"
  echo "DOCKERFILE_CONTEXT=." >> "$GITHUB_ENV"
  echo "Generated Go Dockerfile"

else
  echo "Could not detect language — using nginx fallback"
  echo "BUILD_APP=" >> "$GITHUB_ENV"
fi
