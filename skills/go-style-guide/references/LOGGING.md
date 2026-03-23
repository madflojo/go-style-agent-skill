# Logging

Logging is owned by the application, not by reusable packages.

Packages should:

- return errors
- expose status/results
- provide hooks/callbacks
- avoid emitting logs directly

The goal is to keep packages reusable, deterministic, and testable.

---

## Default Rule: Packages Do Not Log

Avoid in libraries:

- `log.*`
- `fmt.Print*`
- writing to `os.Stdout` / `os.Stderr`
- creating global loggers
- `init()`-time logging setup

Instead:

- propagate errors to the caller
- allow the app/service to decide what to log and how

---

## The Exception: Async / Network / Runtime Packages

Some packages legitimately need to record events because:

- work happens asynchronously
- errors occur outside the initiating call-site
- there is a runtime loop that must continue running
- observability is part of the package's contract (rare)

In those cases, logging may exist, but it must be:

1) **Injected**
2) **Optional**
3) **Standardized on `*slog.Logger`**
4) **Never global**
5) **Safe by default** (no panics, no uncontrolled output)

---

## Preferred Injection Pattern: `*slog.Logger` via Config

```go
type Config struct {
    Logger *slog.Logger
}

type Worker struct {
    log *slog.Logger
}

func New(cfg Config) *Worker {
    // Never force logging on users.
    // If nil, use slog's discard logger.
    log := cfg.Logger
    if log == nil {
        log = slog.New(slog.NewTextHandler(io.Discard, nil))
    }

    return &Worker{log: log}
}
```

### Why discard?

- prevents accidental output during tests
- avoids coupling libraries to process stdout/stderr
- keeps behavior stable and deterministic

---

## Prefer Context-Aware Logging

If a method already accepts `context.Context` and the package must log, prefer
`InfoContext`, `DebugContext`, `WarnContext`, or `ErrorContext`.

```go
func (w *Worker) Run(ctx context.Context, input []byte) error {
    w.log.InfoContext(ctx, "worker started", "size", len(input))

    if err := w.doWork(ctx, input); err != nil {
        w.log.ErrorContext(ctx, "worker failed", "err", err)
        return fmt.Errorf("do work: %w", err)
    }

    return nil
}
```

Why:

- lets trace IDs and request IDs flow from the application into package logs
- keeps logs correlated with the request or operation that produced them
- avoids ad hoc request metadata threading

Prefer stable structured field names for correlation data such as
`request_id`, `trace_id`, or `correlation_id`. These fields make it much
easier to follow a single operation across services and components.

Do not invent a new background context just to satisfy logging. If you do not
have a meaningful context, use the non-context log methods.

---

## Prefer Error Surfacing Over Logging

If something fails, return an error.

```go
func (w *Worker) Run(ctx context.Context, input []byte) ([]byte, error) {
    output, err := w.run(ctx, input)
    if err != nil {
        return nil, fmt.Errorf("run: %w", err)
    }
    return output, nil
}
```

Only log in-package when:

- failure cannot be returned to the caller
- failure happens after the call returns (async)

---

## Async Error Handling: Prefer `OnError` over `errCh`

`errCh` works, but a callback is often cleaner for callers and agents.

### Pattern

- Provide `OnError func(error)` in `Config`
- Default to a no-op function
- Invoke it whenever async work fails
- Still allow the app to decide whether to log, count metrics, or crash

```go
type Config struct {
    Logger  *slog.Logger
    OnError func(error)
}

type Worker struct {
    log    *slog.Logger
    onErr  func(error)
}

func New(cfg Config) *Worker {
    log := cfg.Logger
    if log == nil {
        log = slog.New(slog.NewTextHandler(io.Discard, nil))
    }

    onErr := cfg.OnError
    if onErr == nil {
        onErr = func(error) {}
    }

    return &Worker{
        log:   log,
        onErr: onErr,
    }
}

func (w *Worker) runAsyncTask(ctx context.Context) {
    go func() {
        if err := w.doWork(ctx); err != nil {
            // Prefer surfacing. Logging is optional and caller-controlled.
            w.onErr(err)

            // Optional: log locally if this package's contract demands it.
            // Keep it structured.
            w.log.ErrorContext(ctx, "async task failed", "err", err)
        }
    }()
}
```

### Notes

- `OnError` is the contract; logging is optional.
- If you do log, keep it structured (keys, not formatted strings).
- Avoid spamming logs for transient, expected errors.

---

## When Local Logging is Acceptable

Local logging is acceptable when:

- the package is effectively a runtime (long-running loop)
- errors occur after the initiating call returns
- there is no other mechanism to surface failure in context
- the library is already part of an app boundary layer

Even then:

- default to discard
- document the behavior
- keep log volume predictable

---

## Log Levels and Volume

Use log levels intentionally.

| Level | Catchy rule | Use for |
| --- | --- | --- |
| `Error` | **Errors wake people up.** | Actionable failures that likely need human intervention. |
| `Warn` | **Warnings watch trends.** | Problems that self-correct or become actionable at volume. |
| `Info` | **Info informs.** | Useful operational events and coarse business milestones. |
| `Debug` | **Debug digs deeper.** | Detailed diagnostics, especially on request paths. |
| `Trace` | **Trace tells everything.** | Fine-grained execution details for deep debugging. |

When available, include stable correlation fields like `request_id`,
`trace_id`, or `correlation_id` so important logs can be followed end-to-end.

If the system recovers automatically, do not log at `Error` unless there is
still an unresolved user-visible or operational issue. Successful retries,
fallbacks, and self-healing paths should be `Warn` or `Info` at most.

Request- or event-level `Info` logs are the exception. If used, prefer one per
event, and avoid them in busy or high-throughput services.

On hot request paths, avoid chatty `Info` logs, especially in loops or
per-item processing. Prefer errors, metrics, or `Debug` when the extra detail
is worth it.

Do not log every retry, poll iteration, or expected transient condition at high
severity. Keep volume predictable.

---

## Hot-Path Logging Is a Performance Decision

Logging on a busy request path is not free. Log level, formatting cost, output
destination, and flushing behavior can materially affect throughput and tail
latency.

Be especially careful with:

- per-request `Info` logs
- logs inside tight loops
- logging large payloads or expensive structured values
- synchronous writes on high-throughput paths

If a service needs detailed request-path visibility, prefer:

- metrics for hot-path counting
- `Debug` logs gated behind configuration
- sampled logs for noisy events

Asynchronous logging can reduce request blocking, but it changes the system
contract. If you use it, document:

- buffering behavior
- backpressure behavior
- drop behavior on overload

The logging path should never accidentally become the system bottleneck.

---

## Sensitive Data and Payload Safety

Logs must never become a second data store.

Do not log:

- secrets, tokens, API keys, passwords, cookies, or credentials
- full request or response payloads by default
- raw personal, financial, health, or other sensitive user data
- data that is not required to understand the event

Prefer logging stable identifiers, counts, sizes, types, and redacted summaries
instead of raw payloads.

Good:

- `"correlation_id", correlationID`
- `"request_id", req.ID`
- `"item_count", len(items)`
- `"payload_size", len(body)`

Bad:

- `"authorization", authHeader`
- `"payload", string(body)`
- `"user", user`

When in doubt, log less data and make redaction explicit in the application
layer.

---

## What Not To Do

### Do not create a logger internally that writes to stdout/stderr

```go
// ❌ Avoid
log := slog.New(slog.NewTextHandler(os.Stdout, nil))
```

### Do not swallow errors just because you logged them

```go
// ❌ Avoid
if err != nil {
    c.log.Error("failed", "err", err)
    return nil
}
```

Return errors whenever possible.

---

## Summary

- Libraries do not log by default.
- The application owns logging decisions.
- If logging is necessary, inject `*slog.Logger` via `Config`.
- Prefer context-aware logging when a real `context.Context` is already present.
- Use `Info` for meaningful application events; request/event `Info` logs are
  exceptional, ideally one per event, and often inappropriate for busy
  services.
- Error logs wake people up; use them for actionable failures that likely need human intervention.
- Never log secrets, credentials, or full payloads by default.
- Prefer `OnError func(error)` for async failures; `errCh` is acceptable but less ergonomic.
- Default logging to discard to avoid hidden output and test pollution.
