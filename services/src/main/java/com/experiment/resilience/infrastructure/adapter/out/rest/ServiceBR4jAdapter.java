package com.experiment.resilience.infrastructure.adapter.out.rest;

import com.experiment.resilience.domain.model.ResponseB;
import com.experiment.resilience.domain.port.out.ServiceBPort;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

/**
 * Adapter de saída COM Resilience4j: a mesma chamada HTTP do
 * ServiceBRestAdapter, envolvida por retry e circuit breaker.
 * Usado só na variante r4j. Os parâmetros ficam em application-r4j.yaml.
 *
 * Ordem padrão do Resilience4j: o Retry fica por fora e o CircuitBreaker
 * por dentro, ou seja, cada tentativa passa pelo circuit breaker.
 */
@Component
@Profile("service-a & r4j")
public class ServiceBR4jAdapter implements ServiceBPort {

    private final RestClient restClient;

    public ServiceBR4jAdapter(RestClient.Builder builder,
                              @Value("${app.service-b.url}") String baseUrl) {
        this.restClient = builder.baseUrl(baseUrl).build();
    }

    @Override
    @Retry(name = "serviceB")
    @CircuitBreaker(name = "serviceB")
    public ResponseB fetch(String id) {
        return restClient.get()
                .uri("/api/b/{id}", id)
                .retrieve()
                .body(ResponseB.class);
    }
}
