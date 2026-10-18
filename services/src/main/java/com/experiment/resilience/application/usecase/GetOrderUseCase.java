package com.experiment.resilience.application.usecase;

import com.experiment.resilience.domain.model.OrderResponse;
import com.experiment.resilience.domain.model.StockResponse;
import com.experiment.resilience.domain.port.out.StockServicePort;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;

@Service
@Profile("service-a")
public class GetOrderUseCase {

    private final StockServicePort stockServicePort;

    public GetOrderUseCase(StockServicePort stockServicePort) {
        this.stockServicePort = stockServicePort;
    }

    public OrderResponse execute(String orderId) {
        StockResponse stock = stockServicePort.getStock(orderId);
        return new OrderResponse(orderId, "CONFIRMED", stock);
    }
}
