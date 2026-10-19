package com.experiment.resilience.infrastructure.adapter.in.web;

import com.experiment.resilience.application.usecase.ServiceBUseCase;
import com.experiment.resilience.domain.model.ResponseB;
import org.springframework.context.annotation.Profile;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

/** Adapter de entrada do service-b: expõe GET /api/b/{id}. */
@RestController
@Profile("service-b")
public class ServiceBController {

    private final ServiceBUseCase serviceBUseCase;

    public ServiceBController(ServiceBUseCase serviceBUseCase) {
        this.serviceBUseCase = serviceBUseCase;
    }

    @GetMapping("/api/b/{id}")
    public ResponseB get(@PathVariable String id) {
        return serviceBUseCase.execute(id);
    }
}
