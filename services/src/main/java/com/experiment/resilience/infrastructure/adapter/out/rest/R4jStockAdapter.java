package com.experiment.resilience.infrastructure.adapter.out.rest;

import com.experiment.resilience.domain.model.StockResponse;
import com.experiment.resilience.domain.port.out.StockServicePort;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

@Component
@Profile("r4j")
@ConditionalOnProperty("app.stock-service.url")
public class R4jStockAdapter implements StockServicePort {

    private final RestClient restClient;

    public R4jStockAdapter(RestClient.Builder builder,
                           @Value("${app.stock-service.url}") String baseUrl) {
        this.restClient = builder.baseUrl(baseUrl).build();
    }

    @Override
    @Retry(name = "downstream")
    @CircuitBreaker(name = "downstream")
    public StockResponse getStock(String id) {
        return restClient.get()
                .uri("/api/stock/{id}", id)
                .retrieve()
                .body(StockResponse.class);
    }
}
