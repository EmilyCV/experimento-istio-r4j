package com.experiment.resilience.domain.model;

/**
 * Resposta do service-a: repassa o que recebeu do service-b.
 *
 * @param id       identificador recebido na requisição
 * @param status   situação da chamada ("OK" quando o service-b respondeu)
 * @param serviceB resposta recebida do service-b
 */
public record ResponseA(
        String id,
        String status,
        ResponseB serviceB
) {}
