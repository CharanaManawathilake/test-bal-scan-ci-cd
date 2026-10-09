// Findings at every severity, including high.

import ballerina/crypto;
import ballerina/os;

// ballerina:13 (high) - Hardcoded secret as a configurable default value.
configurable string serviceToken = "replace-me";

// ballerina/os:1 (high) - Command arguments built from user input.
// ballerina:3 (low) - Non isolated public function.
public function startTask(string taskArg) returns os:Process|error {
    return os:exec({value: "/opt/tasks/run", arguments: ["--task", taskArg]});
}

// ballerina/crypto:1 (medium) - Insecure cipher mode (AES-ECB).
public isolated function seal(byte[] plain, byte[16] secret) returns byte[]|error {
    return crypto:encryptAesEcb(plain, secret);
}

// ballerina:1 (low) - Avoid checkpanic.
public isolated function maxRetries() returns int {
    return checkpanic int:fromString("5");
}
