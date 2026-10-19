package com.experiment.resilience.infrastructure.adapter.in.web;

import com.experiment.resilience.application.usecase.ServiceAUseCase;
import com.experiment.resilience.domain.model.ResponseA;
import org.springframework.context.annotation.Profile;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

/** Adapter de entrada do service-a: expõe GET /api/a/{id}. */
@RestController
@Profile("service-a")
public class ServiceAController {

    private final ServiceAUseCase serviceAUseCase;

    public ServiceAController(ServiceAUseCase serviceAUseCase) {
        this.serviceAUseCase = serviceAUseCase;
    }

    @GetMapping("/api/a/{id}")
    public ResponseA get(@PathVariable String id) {
        return serviceAUseCase.execute(id);
    }
}
