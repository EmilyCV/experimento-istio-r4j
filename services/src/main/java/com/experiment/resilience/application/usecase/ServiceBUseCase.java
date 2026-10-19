package com.experiment.resilience.application.usecase;

import com.experiment.resilience.domain.exception.FaultInjectedException;
import com.experiment.resilience.domain.model.FaultConfig;
import com.experiment.resilience.domain.model.ResponseB;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;

/**
 * Caso de uso do service-b: faz um trabalho de CPU curto (padrão 5 ms)
 * e devolve um JSON simples. Também aplica a falha injetada, se houver
 * (no teste sem falhas, a configuração fica sempre em FaultConfig.NONE).
 */
@Service
@Profile("service-b")
public class ServiceBUseCase {

    private final int cpuWorkMs;

    private volatile FaultConfig faultConfig = FaultConfig.NONE;

    // Guarda o resultado do cálculo para o compilador JIT não eliminar o laço.
    private volatile double sink;

    public ServiceBUseCase(@Value("${app.cpu-work-ms:5}") int cpuWorkMs) {
        this.cpuWorkMs = cpuWorkMs;
    }

    public ResponseB execute(String id) {
        FaultConfig fault = this.faultConfig;

        if (fault.shouldInjectDelay()) {
            sleep(fault.delayMs());
        }
        if (fault.shouldInjectError()) {
            throw new FaultInjectedException(fault.errorStatus());
        }

        long start = System.nanoTime();
        simulateCpuWork();
        long elapsedMs = (System.nanoTime() - start) / 1_000_000;

        double value = 9.99 + (Math.abs(id.hashCode()) % 9000) / 100.0;
        return new ResponseB(id, value, elapsedMs);
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

    /** Ocupa a CPU durante cpuWorkMs milissegundos com contas simples. */
    private void simulateCpuWork() {
        long target = cpuWorkMs * 1_000_000L;
        long start = System.nanoTime();
        double result = 0;
        while (System.nanoTime() - start < target) {
            result += Math.sin(result + 1);
        }
        sink = result;
    }

    private void sleep(int millis) {
        try {
            Thread.sleep(millis);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
