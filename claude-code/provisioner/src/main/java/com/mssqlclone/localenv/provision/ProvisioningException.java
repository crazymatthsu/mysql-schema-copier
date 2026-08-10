package com.mssqlclone.localenv.provision;

/** Raised when the local environment could not be brought to the configured state. */
public class ProvisioningException extends RuntimeException {

    public ProvisioningException(String message) {
        super(message);
    }

    public ProvisioningException(String message, Throwable cause) {
        super(message, cause);
    }
}
