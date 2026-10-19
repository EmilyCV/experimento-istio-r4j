# Imagem única do experimento (service-a e service-b).
# O jar é compilado ANTES, na máquina, com:  mvn -f services/pom.xml clean package -DskipTests
# Assim não é preciso baixar a imagem do Maven; o Docker só copia o jar.
#
# Uso (na pasta raiz do projeto):
#   docker build -t resilience-service:1.0 services
# Imagem base fixada pelo digest (Temurin 21.0.12.1, baixada em 2026-10-18), para a execução ser reproduzível.
FROM eclipse-temurin:21-jre-alpine@sha256:51ab5e3302e7141ce665ca3ea85e8b5cd648eafbc3c0c90dd79d6537684e4555
WORKDIR /app
COPY target/resilience-service-1.0.0.jar app.jar
EXPOSE 8080
# MaxRAMPercentage=75: a JVM usa até 75% do limite de memória do container para o heap.
ENTRYPOINT ["java", "-XX:+UseG1GC", "-XX:MaxRAMPercentage=75.0", "-jar", "app.jar"]
