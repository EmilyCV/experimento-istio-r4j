package com.experiment.resilience.infrastructure.adapter.out.rest;

import com.experiment.resilience.domain.model.ResponseB;
import com.experiment.resilience.domain.port.out.ServiceBPort;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

/**
 * Adapter de saída SEM resiliência: uma chamada HTTP simples ao service-b.
 * Usado nas variantes baseline e istio (profile "r4j" desligado).
 * Na variante istio, o retry e o circuit breaker ficam no sidecar.
 */
@Component
@Profile("service-a & !r4j")
public class ServiceBRestAdapter implements ServiceBPort {

    private final RestClient restClient;

    public ServiceBRestAdapter(RestClient.Builder builder,
                               @Value("${app.service-b.url}") String baseUrl) {
        this.restClient = builder.baseUrl(baseUrl).build();
    }

    @Override
    public ResponseB fetch(String id) {
        return restClient.get()
                .uri("/api/b/{id}", id)
                .retrieve()
                .body(ResponseB.class);
    }
}
