package com.experiment.resilience.domain.model;

public record PriceResponse(
        String productId,
        double price,
        long computeTimeMs
) {}
