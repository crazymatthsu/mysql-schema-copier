package com.mssqlclone.localenv.config;

/** Raised when {@code databases.yaml} is missing, unreadable, or internally inconsistent. */
public class ConfigException extends RuntimeException {

    public ConfigException(String message) {
        super(message);
    }

    public ConfigException(String message, Throwable cause) {
        super(message, cause);
    }
}
