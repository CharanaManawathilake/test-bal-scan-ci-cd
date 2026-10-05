// Findings only in test sources; exclude-tests should drop all of them.

import ballerina/test;

// ballerina:1 (low) - Avoid checkpanic.
// ballerina:10 (low) - Self assignment.
@test:Config {}
function testGreeting() {
    int count = checkpanic int:fromString("1");
    count = count;
    test:assertEquals(greeting(), "hello");
}
