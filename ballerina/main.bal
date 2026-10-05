// Language-rule violations (Code Smells -> SARIF level "note").

import ballerina/io;

// ballerina:3 - Non isolated public function.
public function greet() {
    io:println("bal scan CI/CD demo");
}

// ballerina:2 - Unused function parameter (`verbose` is never read).
function report(int count, boolean verbose) {
    io:println("count: ", count);
}

// ballerina:1 - Avoid checkpanic.
public function loadLimit() returns int {
    return checkpanic int:fromString("42");
}

// ballerina:10 - Self assignment.
// ballerina:12 - Invalid range expression (9 ... 0 never iterates).
public function countdown() {
    int counter = 3;
    counter = counter;
    foreach int i in 9 ... 0 {
        io:println(i);
    }
}

public function main() {
    greet();
    report(loadLimit(), true);
    countdown();
}
