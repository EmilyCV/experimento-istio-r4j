package com.experiment.resilience.domain.exception;

/**
 * Lançada pelo service-b quando uma falha é injetada de propósito.
 * Guarda o código HTTP que deve ser devolvido ao chamador.
 */
public class FaultInjectedException extends RuntimeException {

    private final int status;

    public FaultInjectedException(int status) {
        super("Falha injetada: HTTP " + status);
        this.status = status;
    }

    public int getStatus() {
        return status;
    }
}
