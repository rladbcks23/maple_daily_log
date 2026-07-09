package com.mapledailylog.nexon;

public class NexonApiException extends RuntimeException {

    public NexonApiException(String message) {
        super(message);
    }

    public NexonApiException(String message, Throwable cause) {
        super(message, cause);
    }
}
