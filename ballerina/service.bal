// HTTP rules.

import ballerina/http;

service /api on new http:Listener(9090) {

    // ballerina/http:1 - Avoid allowing default resource accessor.
    resource function default orders(string id) returns string {
        return "order " + id;
    }

    // ballerina/http:2 - Avoid permissive CORS.
    @http:ResourceConfig {
        cors: {
            allowOrigins: ["*"]
        }
    }
    resource function get status() returns string {
        return "ok";
    }

    // ballerina/http:4 - Open redirect.
    resource function get go(string target) returns http:TemporaryRedirect {
        return {
            headers: {
                "Location": target
            }
        };
    }
}
