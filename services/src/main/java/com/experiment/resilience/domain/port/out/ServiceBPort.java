package com.experiment.resilience.domain.port.out;

import com.experiment.resilience.domain.model.ResponseB;

/**
 * Port de saída: o que o service-a precisa do service-b.
 * O caso de uso depende só desta interface; quem a implementa
 * (com ou sem Resilience4j) é escolhido pelo profile do Spring.
 */
public interface ServiceBPort {

    ResponseB fetch(String id);
}
