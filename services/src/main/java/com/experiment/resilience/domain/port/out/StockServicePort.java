package com.experiment.resilience.domain.port.out;

import com.experiment.resilience.domain.model.StockResponse;

public interface StockServicePort {

    StockResponse getStock(String id);
}
