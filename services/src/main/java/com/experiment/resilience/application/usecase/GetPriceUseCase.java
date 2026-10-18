package com.experiment.resilience.application.usecase;

import com.experiment.resilience.domain.model.FaultConfig;
import com.experiment.resilience.domain.model.PriceResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;

@Service
@Profile("service-c")
public class GetPriceUseCase {

    private volatile FaultConfig faultConfig = FaultConfig.NONE;

    private final int cpuWorkMs;

    public GetPriceUseCase(@Value("${app.cpu-work-ms:5}") int cpuWorkMs) {
        this.cpuWorkMs = cpuWorkMs;
    }

    public PriceResponse execute(String productId) {
        FaultConfig fault = this.faultConfig;

        if (fault.shouldInjectDelay()) {
            sleep(fault.delayMs());
        }

        if (fault.shouldInjectError()) {
            throw new FaultInjectedException(fault.errorStatus());
        }

        long start = System.nanoTime();
        simulateCpuWork();
        long elapsed = (System.nanoTime() - start) / 1_000_000;

        double price = 9.99 + (Math.abs(productId.hashCode()) % 9000) / 100.0;
        return new PriceResponse(productId, price, elapsed);
    }

    public void configureFault(FaultConfig config) {
        this.faultConfig = config;
    }

    public void resetFault() {
        this.faultConfig = FaultConfig.NONE;
    }

    public FaultConfig currentFault() {
        return this.faultConfig;
    }

    private void simulateCpuWork() {
        long target = cpuWorkMs * 1_000_000L;
        long start = System.nanoTime();
        double result = 0;
        while (System.nanoTime() - start < target) {
            result += Math.sin(result + 1);
        }
        if (result == Double.NaN) throw new IllegalStateException();
    }

    private void sleep(int millis) {
        try {
            Thread.sleep(millis);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    public static class FaultInjectedException extends RuntimeException {
        private final int status;

        public FaultInjectedException(int status) {
            super("Injected fault: HTTP " + status);
            this.status = status;
        }

        public int getStatus() {
            return status;
        }
    }
}
