package com.experiment.resilience.domain.model;

public record OrderResponse(
        String orderId,
        String status,
        StockResponse stock
) {}
