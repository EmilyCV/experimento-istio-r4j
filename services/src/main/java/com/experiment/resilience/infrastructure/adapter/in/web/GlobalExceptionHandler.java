package com.experiment.resilience.infrastructure.adapter.in.web;

import com.experiment.resilience.domain.exception.FaultInjectedException;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.Map;

/** Converte a falha injetada no código HTTP escolhido (ex.: 503). */
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(FaultInjectedException.class)
    public ResponseEntity<Map<String, Object>> handleFault(FaultInjectedException ex) {
        return ResponseEntity.status(ex.getStatus())
                .body(Map.of("error", ex.getMessage(), "status", ex.getStatus()));
    }
}
