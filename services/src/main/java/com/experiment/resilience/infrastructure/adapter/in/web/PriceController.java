package com.experiment.resilience.infrastructure.adapter.in.web;

import com.experiment.resilience.application.usecase.GetPriceUseCase;
import com.experiment.resilience.domain.model.PriceResponse;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.context.annotation.Profile;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

@RestController
@Profile("service-c")
public class PriceController {

    private final GetPriceUseCase getPriceUseCase;
    private final Counter requestCounter;

    public PriceController(GetPriceUseCase getPriceUseCase, MeterRegistry registry) {
        this.getPriceUseCase = getPriceUseCase;
        this.requestCounter = Counter.builder("service_c_requests_total")
                .description("Total requests received by service-c (measures retry multiplication)")
                .register(registry);
    }

    @GetMapping("/api/price/{id}")
    public PriceResponse getPrice(@PathVariable String id) {
        requestCounter.increment();
        return getPriceUseCase.execute(id);
    }
}
