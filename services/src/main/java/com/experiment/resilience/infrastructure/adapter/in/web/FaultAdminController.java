package com.experiment.resilience.infrastructure.adapter.in.web;

import com.experiment.resilience.application.usecase.ServiceBUseCase;
import com.experiment.resilience.domain.model.FaultConfig;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Profile;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * Endpoint administrativo para injetar falhas no service-b.
 * DESLIGADO por padrão: só existe quando app.fault-admin.enabled=true.
 * Não é usado no teste sem falhas; fica pronto para um teste futuro.
 */
@RestController
@Profile("service-b")
@ConditionalOnProperty(name = "app.fault-admin.enabled", havingValue = "true")
public class FaultAdminController {

    private final ServiceBUseCase serviceBUseCase;

    public FaultAdminController(ServiceBUseCase serviceBUseCase) {
        this.serviceBUseCase = serviceBUseCase;
    }

    @PostMapping("/admin/fault")
    public Map<String, Object> configureFault(@RequestBody FaultRequest request) {
        if (Boolean.TRUE.equals(request.reset())) {
            serviceBUseCase.resetFault();
            return Map.of("status", "reset", "fault", serviceBUseCase.currentFault());
        }

        FaultConfig config = new FaultConfig(
                request.delayMs() != null ? request.delayMs() : 0,
                request.delayPercent() != null ? request.delayPercent() : 0,
                request.errorPercent() != null ? request.errorPercent() : 0,
                request.errorStatus() != null ? request.errorStatus() : 503,
                Boolean.TRUE.equals(request.down())
        );
        serviceBUseCase.configureFault(config);
        return Map.of("status", "configured", "fault", config);
    }

    @GetMapping("/admin/fault")
    public FaultConfig currentFault() {
        return serviceBUseCase.currentFault();
    }

    public record FaultRequest(
            Integer delayMs,
            Integer delayPercent,
            Integer errorPercent,
            Integer errorStatus,
            Boolean down,
            Boolean reset
    ) {}
}
