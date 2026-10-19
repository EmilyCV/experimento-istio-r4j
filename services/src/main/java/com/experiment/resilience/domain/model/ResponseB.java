package com.experiment.resilience.domain.model;

/**
 * Resposta do service-b.
 *
 * @param id        identificador recebido na requisição
 * @param value     valor calculado a partir do id (só para a resposta não ser vazia)
 * @param cpuTimeMs tempo gasto no trabalho de CPU simulado, em milissegundos
 */
public record ResponseB(
        String id,
        double value,
        long cpuTimeMs
) {}
