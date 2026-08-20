# Deadline workers and client trust

`DodoPayments.ReqClient` is the supported HTTP transport. The public
`DodoPayments.ClientModule` behaviour also permits a company to integrate Tesla
or an internal HTTP stack, but replacement implementations and their dependencies
are trusted application code. They are not sandboxed plugins.

The SDK root supervisor owns the short-lived worker boundary described here.
When asynchronous telemetry is enabled at application startup it also owns a
bounded telemetry task supervisor; the default request-bounded mode does not
start that subtree. Custom-client pools and other long-lived resources remain
application-owned.

## Why HTTP work runs in a Task

The `:timeout` option is a total wall-clock deadline. Validation, request
encoding, API-key resolution, telemetry handlers, every network attempt,
response decoding, and retry backoff consume one shared budget. Passing a
timeout to the HTTP library is insufficient because a key provider, telemetry
handler, custom Req request step, decoder, or replacement client can ignore it
or block before the HTTP library runs.

The SDK therefore evaluates preparation, synchronous telemetry callbacks, each
`ClientModule.request/2` call, and response decoding in short-lived Tasks. It
waits only for the remaining budget and brutally terminates a worker that does
not finish. This makes the deadline enforceable instead of merely checking
elapsed time after a blocking callback eventually returns.

```text
application caller
    |
    +-- telemetry Task, when handlers are attached
    |
    +-- supervised non-linked preparation Task
    |      validation, encoding, key provider
    |
    +-- supervised non-linked attempt Task
    |      ReqClient or replacement ClientModule
    |
    +-- supervised non-linked decoding Task
           JSON decoding and response-schema conversion
```

Telemetry execution uses a deadline worker only when at least one handler is
attached. An attached logical-call handler that exhausts the remaining budget
is terminated. Attempt-start and retry handlers retain a small follow-up
reserve so emitting one of those events cannot itself consume the whole budget
for the dispatch it announces. A final telemetry event may still be omitted if
no budget remains to run its handlers.

Each Task receives a snapshot of the caller's non-system process dictionary and
Logger metadata. That preserves Req instrumentation, `Req.Test` ownership,
process-local tracing, and runtime key providers while retaining the Task's own
BEAM bookkeeping entries.

## Failures the SDK contains

The request engine converts the failures expected at an HTTP boundary into
normal SDK error values:

| Callback behavior | SDK behavior |
| --- | --- |
| Returns `HTTP.Response` | Validates and decodes the response |
| Returns `HTTP.TransportError` | Applies replay and outcome policy |
| Returns another value | Returns a transport error, or `OutcomeUnknown` for a consequential mutation whose delivery cannot be proven absent |
| Raises an ordinary exception | Returns a transport or preparation error |
| Throws or exits normally | Returns a transport or preparation error |
| Exceeds the remaining deadline | Terminates the worker and returns `TimeoutError` or `OutcomeUnknown` |

For consequential mutations, a timeout or uncertain delivery remains
`DodoPayments.Error.OutcomeUnknown`. Its `replay` field distinguishes an unsafe
repeat from an identical replay protected by stable idempotency values. Killing
a local worker cannot undo a request that may already have reached Dodo.

## Supervised worker boundary

Workers are started non-linked under the SDK's deadline task supervisor. An
ordinary exception, throw, exit, invalid adapter value, timeout, or hard worker
termination is converted into the normal preparation, transport, timeout, or
`OutcomeUnknown` result. A hard kill cannot terminate the SDK caller.

The supervisor start call is also made behind the deadline boundary. If the
task supervisor is unavailable, restarting, or fails to reply, the caller gets
the same bounded timeout result; it does not exit or wait indefinitely before
the callback begins.

This containment is process isolation, not delivery durability. If a mutation
may have reached Dodo before its worker died, the result remains uncertain and
the application must reconcile before replaying. Custom `ClientModule` code,
custom Req steps, and their dependencies are still trusted application code:
they must avoid deliberately killing the callback and should return
`DodoPayments.HTTP.TransportError` for known failures.

## Requirements for custom clients

A replacement client should:

1. return `DodoPayments.HTTP.TransportError` for every transport failure;
2. never deliberately kill its callback process;
3. avoid linking the callback to unmanaged worker processes;
4. respect `request.timeout` so SDK termination remains a last resort;
5. classify uncertain delivery as `:unknown`;
6. let the application supervise any pools or long-lived workers it owns.

Applications should also retain stable business identifiers around payment
mutations. That makes reconciliation possible even if the entire request
handler, job, or node disappears rather than returning an SDK value.
