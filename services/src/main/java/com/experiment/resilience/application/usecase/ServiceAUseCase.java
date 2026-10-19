package com.experiment.resilience.application.usecase;

import com.experiment.resilience.domain.model.ResponseA;
import com.experiment.resilience.domain.model.ResponseB;
import com.experiment.resilience.domain.port.out.ServiceBPort;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;

/**
 * Caso de uso do service-a: chama o service-b e monta a resposta.
 * Não sabe se existe retry ou circuit breaker; isso fica no adapter
 * (variante r4j) ou no sidecar do Istio (variante istio).
 */
@Service
@Profile("service-a")
public class ServiceAUseCase {

    private final ServiceBPort serviceBPort;

    public ServiceAUseCase(ServiceBPort serviceBPort) {
        this.serviceBPort = serviceBPort;
    }

    public ResponseA execute(String id) {
        ResponseB responseB = serviceBPort.fetch(id);
        return new ResponseA(id, "OK", responseB);
    }
}
