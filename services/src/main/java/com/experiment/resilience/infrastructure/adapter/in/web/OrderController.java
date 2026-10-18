package com.experiment.resilience.infrastructure.adapter.in.web;

import com.experiment.resilience.application.usecase.GetOrderUseCase;
import com.experiment.resilience.domain.model.OrderResponse;
import org.springframework.context.annotation.Profile;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

@RestController
@Profile("service-a")
public class OrderController {

    private final GetOrderUseCase getOrderUseCase;

    public OrderController(GetOrderUseCase getOrderUseCase) {
        this.getOrderUseCase = getOrderUseCase;
    }

    @GetMapping("/api/order/{id}")
    public OrderResponse getOrder(@PathVariable String id) {
        return getOrderUseCase.execute(id);
    }
}
