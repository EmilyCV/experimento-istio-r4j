package com.experiment.resilience.domain.model;

import java.util.concurrent.ThreadLocalRandom;

/**
 * Configuração de injeção de falhas do service-b.
 * Não é usada no teste sem falhas; fica pronta para um teste futuro.
 *
 * @param delayMs      atraso a injetar, em milissegundos
 * @param delayPercent porcentagem das requisições que recebem o atraso
 * @param errorPercent porcentagem das requisições que recebem erro
 * @param errorStatus  código HTTP do erro injetado (ex.: 503)
 * @param down         se verdadeiro, todas as requisições falham
 */
public record FaultConfig(
        int delayMs,
        int delayPercent,
        int errorPercent,
        int errorStatus,
        boolean down
) {
    /** Sem falhas: é o estado inicial do service-b. */
    public static final FaultConfig NONE = new FaultConfig(0, 0, 0, 503, false);

    public boolean shouldInjectDelay() {
        if (delayMs <= 0 || delayPercent <= 0) return false;
        return ThreadLocalRandom.current().nextInt(100) < delayPercent;
    }

    public boolean shouldInjectError() {
        if (down) return true;
        if (errorPercent <= 0) return false;
        return ThreadLocalRandom.current().nextInt(100) < errorPercent;
    }
}
