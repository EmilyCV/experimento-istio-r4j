package com.experiment.resilience.infrastructure.adapter.in.web;

import com.experiment.resilience.application.usecase.GetPriceUseCase;
import com.experiment.resilience.domain.model.FaultConfig;
import org.springframework.context.annotation.Profile;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
@Profile("service-c")
public class FaultAdminController {

    private final GetPriceUseCase getPriceUseCase;

    public FaultAdminController(GetPriceUseCase getPriceUseCase) {
        this.getPriceUseCase = getPriceUseCase;
    }

    @PostMapping("/admin/fault")
    public Map<String, Object> configureFault(@RequestBody FaultRequest request) {
        if (Boolean.TRUE.equals(request.reset())) {
            getPriceUseCase.resetFault();
            return Map.of("status", "reset", "fault", getPriceUseCase.currentFault());
        }

        FaultConfig config = new FaultConfig(
                request.delayMs() != null ? request.delayMs() : 0,
                request.delayPercent() != null ? request.delayPercent() : 0,
                request.errorPercent() != null ? request.errorPercent() : 0,
                request.errorStatus() != null ? request.errorStatus() : 503,
                Boolean.TRUE.equals(request.down())
        );
        getPriceUseCase.configureFault(config);
        return Map.of("status", "configured", "fault", config);
    }

    @GetMapping("/admin/fault")
    public FaultConfig currentFault() {
        return getPriceUseCase.currentFault();
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
