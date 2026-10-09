// Medium and low findings but no high ones: the default high gate passes,
// a medium gate fails.

import ballerina/crypto;

// ballerina/crypto:1 (medium) - Insecure cipher mode (AES-ECB).
public isolated function seal(byte[] plain, byte[16] secret) returns byte[]|error {
    return crypto:encryptAesEcb(plain, secret);
}

// ballerina:1 (low) - Avoid checkpanic.
public isolated function maxRetries() returns int {
    return checkpanic int:fromString("5");
}
