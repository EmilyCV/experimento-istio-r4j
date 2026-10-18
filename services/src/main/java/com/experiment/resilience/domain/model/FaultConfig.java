package com.experiment.resilience.domain.model;

import java.util.concurrent.ThreadLocalRandom;

public record FaultConfig(
        int delayMs,
        int delayPercent,
        int errorPercent,
        int errorStatus,
        boolean down
) {
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
