// Findings at every severity, including high.

import ballerina/crypto;
import ballerina/os;

// ballerina:13 (high) - Hardcoded secret as a configurable default value.
configurable string apiKey = "changeme";

// ballerina/os:1 (high) - Command arguments built from user input.
// ballerina:3 (low) - Non isolated public function.
public function runJob(string userInput) returns os:Process|error {
    return os:exec({value: "/usr/bin/runner", arguments: ["--job", userInput]});
}

// ballerina/crypto:1 (medium) - Insecure cipher mode (AES-ECB).
public isolated function encrypt(byte[] data, byte[16] key) returns byte[]|error {
    return crypto:encryptAesEcb(data, key);
}

// ballerina:1 (low) - Avoid checkpanic.
public isolated function loadLimit() returns int {
    return checkpanic int:fromString("42");
}
