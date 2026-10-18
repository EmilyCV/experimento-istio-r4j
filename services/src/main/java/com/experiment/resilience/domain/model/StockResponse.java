package com.experiment.resilience.domain.model;

public record StockResponse(
        String productId,
        int quantity,
        PriceResponse price
) {}
