// Crypto, OS and logging rules.

import ballerina/crypto;
import ballerina/log;
import ballerina/os;

// ballerina:13 - Hardcoded secret as a configurable default value.
configurable string apiSecret = "changeme";

// ballerina/crypto:1 - Insecure cipher mode (AES-ECB).
public isolated function encrypt(byte[] data, byte[16] key) returns byte[]|error {
    return crypto:encryptAesEcb(data, key);
}

// ballerina/crypto:2 - Weak BCrypt work factor.
public isolated function hashPassword(string password) returns string|error {
    return crypto:hashBcrypt(password, 4);
}

// ballerina/os:1 - Command arguments built from user input.
public function runJob(string userInput) returns os:Process|error {
    string[] args = ["--job", userInput];
    return os:exec({
        value: "/usr/bin/runner",
        arguments: args
    });
}

// ballerina/log:1 - Configurable (potentially sensitive) value logged.
public function logStartup() {
    log:printInfo(apiSecret);
}
