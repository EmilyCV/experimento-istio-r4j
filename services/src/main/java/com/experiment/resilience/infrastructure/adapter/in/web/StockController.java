package com.experiment.resilience.infrastructure.adapter.in.web;

import com.experiment.resilience.application.usecase.GetStockUseCase;
import com.experiment.resilience.domain.model.StockResponse;
import org.springframework.context.annotation.Profile;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

@RestController
@Profile("service-b")
public class StockController {

    private final GetStockUseCase getStockUseCase;

    public StockController(GetStockUseCase getStockUseCase) {
        this.getStockUseCase = getStockUseCase;
    }

    @GetMapping("/api/stock/{id}")
    public StockResponse getStock(@PathVariable String id) {
        return getStockUseCase.execute(id);
    }
}
