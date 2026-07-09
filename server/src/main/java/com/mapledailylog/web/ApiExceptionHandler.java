package com.mapledailylog.web;

import com.mapledailylog.nexon.NexonApiException;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class ApiExceptionHandler {

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<Map<String, Object>> handleIllegalArgument(IllegalArgumentException exception) {
        return ResponseEntity.badRequest().body(error("bad_request", exception.getMessage()));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<Map<String, Object>> handleValidation(MethodArgumentNotValidException exception) {
        return ResponseEntity.badRequest().body(error("validation_failed", "Request validation failed."));
    }

    @ExceptionHandler(NexonApiException.class)
    public ResponseEntity<Map<String, Object>> handleNexonApi(NexonApiException exception) {
        return ResponseEntity.status(HttpStatus.BAD_GATEWAY)
                .body(error("nexon_api_error", exception.getMessage()));
    }

    private Map<String, Object> error(String code, String message) {
        return Map.of(
                "status", "error",
                "code", code,
                "message", message
        );
    }
}
