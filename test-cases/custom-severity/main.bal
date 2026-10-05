// Medium and low findings but no high ones: the default high gate passes,
// a medium gate fails.

import ballerina/crypto;

// ballerina/crypto:1 (medium) - Insecure cipher mode (AES-ECB).
public isolated function encrypt(byte[] data, byte[16] key) returns byte[]|error {
    return crypto:encryptAesEcb(data, key);
}

// ballerina:1 (low) - Avoid checkpanic.
public isolated function loadLimit() returns int {
    return checkpanic int:fromString("42");
}
