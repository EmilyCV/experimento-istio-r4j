package com.experiment.resilience.infrastructure.adapter.out.rest;

import com.experiment.resilience.domain.model.PriceResponse;
import com.experiment.resilience.domain.port.out.PriceServicePort;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

@Component
@Profile("!r4j")
@ConditionalOnProperty("app.price-service.url")
public class PriceRestAdapter implements PriceServicePort {

    private final RestClient restClient;

    public PriceRestAdapter(RestClient.Builder builder,
                            @Value("${app.price-service.url}") String baseUrl) {
        this.restClient = builder.baseUrl(baseUrl).build();
    }

    @Override
    public PriceResponse getPrice(String id) {
        return restClient.get()
                .uri("/api/price/{id}", id)
                .retrieve()
                .body(PriceResponse.class);
    }
}
