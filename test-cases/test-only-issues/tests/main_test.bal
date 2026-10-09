// Findings only in test sources; exclude-tests should drop all of them.

import ballerina/test;

// ballerina:1 (low) - Avoid checkpanic.
// ballerina:10 (low) - Self assignment.
@test:Config {}
function testGreeting() {
    int attempts = checkpanic int:fromString("3");
    attempts = attempts;
    test:assertEquals(greeting(), "hello");
}
