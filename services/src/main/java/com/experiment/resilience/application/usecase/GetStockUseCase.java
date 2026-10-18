package com.experiment.resilience.application.usecase;

import com.experiment.resilience.domain.model.PriceResponse;
import com.experiment.resilience.domain.model.StockResponse;
import com.experiment.resilience.domain.port.out.PriceServicePort;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;

@Service
@Profile("service-b")
public class GetStockUseCase {

    private final PriceServicePort priceServicePort;

    public GetStockUseCase(PriceServicePort priceServicePort) {
        this.priceServicePort = priceServicePort;
    }

    public StockResponse execute(String productId) {
        PriceResponse price = priceServicePort.getPrice(productId);
        int quantity = 100 + (productId.hashCode() & 0x7F);
        return new StockResponse(productId, quantity, price);
    }
}
