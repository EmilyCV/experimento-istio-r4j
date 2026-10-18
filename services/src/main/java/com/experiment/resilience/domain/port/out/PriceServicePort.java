package com.experiment.resilience.domain.port.out;

import com.experiment.resilience.domain.model.PriceResponse;

public interface PriceServicePort {

    PriceResponse getPrice(String id);
}
