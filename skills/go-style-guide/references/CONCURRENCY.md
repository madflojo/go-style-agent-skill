# Concurrency (Goroutine Lifecycle and Synchronization)

Every goroutine is a commitment. If you start one, you own its lifecycle.

In this style guide, **concurrency must be explicit, cancellable, and
observable**. Fire-and-forget goroutines are a liability. Shared state
requires documented synchronization. Shutdown must be graceful.

## Table of Contents

- [Goroutine Lifecycle Management](#goroutine-lifecycle-management)
- [Context Propagation](#context-propagation)
- [Graceful Shutdown](#graceful-shutdown)
- [Mutex vs Atomic Decisions](#mutex-vs-atomic-decisions)
- [Channel Patterns](#channel-patterns)
- [Common Concurrency Pitfalls](#common-concurrency-pitfalls)
- [What Not To Do](#what-not-to-do)
- [Summary](#summary)

---

## Goroutine Lifecycle Management

### 1. Every Goroutine Must Have a Shutdown Path

If you spawn a goroutine, there must be a way to stop it. The owner of the
goroutine is responsible for its cancellation.

Good:

```go
func (w *Worker) Start(ctx context.Context) {
    w.wg.Add(1)
    go func() {
        defer w.wg.Done()
        for {
            select {
            case <-ctx.Done():
                return
            case job := <-w.jobs:
                w.process(ctx, job)
            }
        }
    }()
}
```

Bad:

```go
func (w *Worker) Start() {
    go func() {
        for job := range w.jobs {
            w.process(context.Background(), job)
        }
    }()
}
```

The bad example has no cancellation path. If nothing closes `w.jobs`, the
goroutine leaks forever.

---

### 2. Use `context.Context` for Cancellation

Context is the standard cancellation mechanism in Go. Pass it from the
caller into every goroutine that does meaningful work.

```go
func (w *Worker) Run(ctx context.Context) error {
    for {
        select {
        case <-ctx.Done():
            return ctx.Err()
        case msg := <-w.inbox:
            if err := w.handle(ctx, msg); err != nil {
                w.log.Error("handle failed", "err", err)
            }
        }
    }
}
```

Never use `context.Background()` inside a long-lived goroutine unless it
is the true top-level entry point.

---

### 3. Avoid Fire-and-Forget Goroutines

Fire-and-forget is almost always wrong. If a goroutine is truly
best-effort and its result does not matter, document it explicitly.

Acceptable (documented):

```go
// FlushAsync sends buffered metrics in the background.
// Errors are intentionally ignored; flush is best-effort.
func (m *Metrics) FlushAsync() {
    go func() {
        _ = m.flush()
    }()
}
```

If you cannot write a clear justification comment, the goroutine should
not be fire-and-forget.

### 4. Add Jitter to Recurring Background Work

Periodic jobs that all wake up on the same schedule often create avoidable
resource spikes.

This applies to:

- cache refresh loops
- cleanup jobs
- pollers
- background sync tasks
- retry loops

If many workers run the same interval, add a small amount of jitter so they do
not synchronize and hammer the same dependency or CPU window at once.

Jitter does not fix bad architecture, but it often prevents self-inflicted
traffic storms and periodic contention spikes.

---

### 5. Use `defer` for cleanup in the scope that acquires the resource

If a function opens, locks, or starts something that must be cleaned up on all
return paths, use `defer` immediately after the successful acquisition.

Typical cases include:

- `file.Close()`
- `resp.Body.Close()`
- `mu.Unlock()`
- `wg.Done()`

Example:

```go
resp, err := httpClient.Do(req)
if err != nil {
    return fmt.Errorf("do request: %w", err)
}
defer resp.Body.Close()
```

This keeps cleanup attached to ownership and prevents leaks when later branches
return early.

---

## Context Propagation

### 1. Accept `context.Context` as the First Parameter

This is not optional. Functions that do I/O, spawn goroutines, or may
block must accept context as the first argument.

Good:

```go
func (s *Server) Handle(ctx context.Context, req *Request) (*Response, error)
```

Bad:

```go
func (s *Server) Handle(req *Request, ctx context.Context) (*Response, error)
```

When using standard-library or common library APIs that support context, use
the context-aware form instead of the non-context variant. Prefer calls such as
`sql.DB.QueryContext`, `sql.DB.ExecContext`, `http.NewRequestWithContext`, and
similar APIs so cancellation and deadlines actually reach the blocking I/O.

---

### 2. Never Store Contexts in Structs

Contexts are request-scoped. Storing them in structs creates stale
references and breaks cancellation semantics.

Bad:

```go
type Worker struct {
    ctx context.Context // ❌ stale after first request
}
```

Good:

```go
type Worker struct {
    // no stored context
}

func (w *Worker) Run(ctx context.Context) error {
    // ctx is passed per-call
    return w.process(ctx)
}
```

The one narrow exception is storing a context derived from a
constructor-provided parent for controlling the lifecycle of background
goroutines/connections/etc. owned by the struct. Even then, prefer passing context through
`Start(ctx)` or `Run(ctx)` methods where it makes sense.

---

### 3. Use Context for Cancellation, Not for Passing Business Data

Context values are for request-scoped metadata that crosses API boundaries
(trace IDs, auth tokens). They are not a replacement for function
parameters.

Bad:

```go
ctx = context.WithValue(ctx, "userID", 42)
id := ctx.Value("userID").(int) // fragile, untyped
```

Good:

```go
func (s *Server) Handle(ctx context.Context, userID int, req *Request) error
```

If you must use context values, define unexported key types to avoid
collisions:

```go
type ctxKey struct{}

func WithTraceID(ctx context.Context, id string) context.Context {
    return context.WithValue(ctx, ctxKey{}, id)
}

func TraceID(ctx context.Context) string {
    v, _ := ctx.Value(ctxKey{}).(string)
    return v
}
```

---

## Graceful Shutdown

### 1. Long-Lived Services Must Implement `Close()` or `Stop()`

Any struct that owns goroutines, connections, or background work must
provide a method to tear it down cleanly.

```go
// Worker processes jobs from a queue in the background.
type Worker struct {
    cancel context.CancelFunc
    wg     sync.WaitGroup
    log    *slog.Logger
}

// New creates a Worker. Call Start to begin processing and Close to stop.
func New(cfg Config) (*Worker, error) {
    log := cfg.Logger
    if log == nil {
        log = slog.New(slog.NewTextHandler(io.Discard, nil))
    }
    return &Worker{log: log}, nil
}

// Start begins background processing. It is safe to call Close to drain.
func (w *Worker) Start(ctx context.Context) {
    ctx, w.cancel = context.WithCancel(ctx)
    w.wg.Add(1)
    go func() {
        defer w.wg.Done()
        w.run(ctx)
    }()
}

// Close signals shutdown and waits for the background goroutine to finish.
func (w *Worker) Close() {
    w.cancel()
    w.wg.Wait()
}
```

This pattern gives callers a clean contract:

- `Start` begins work
- `Close` stops it and blocks until drained

---

### 2. Signal Handling + Graceful Drain

Application entry points should wire OS signals to context cancellation.

```go
func main() {
    ctx, stop := signal.NotifyContext(context.Background(),
        os.Interrupt, syscall.SIGTERM)
    defer stop()

    srv, err := server.New(server.Config{
        Addr:   ":8080",
        Logger: slog.Default(),
    })
    if err != nil {
        slog.Error("failed to create server", "err", err)
        os.Exit(1)
    }

    srv.Start(ctx)

    // Block until signal received.
    <-ctx.Done()
    slog.Info("shutting down")

    // Give in-flight work time to drain.
    shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()

    if err := srv.Shutdown(shutdownCtx); err != nil {
        slog.Error("shutdown error", "err", err)
        os.Exit(1)
    }

    slog.Info("shutdown complete")
}
```

Key points:

- `signal.NotifyContext` (Go 1.16+) is the cleanest signal-to-context bridge
- Shutdown gets its own timeout context separate from the cancelled parent
- `main` is the right place for signal handling, not libraries

For network services, graceful shutdown should usually follow this order:

1. fail readiness checks so new traffic stops arriving
2. stop accepting new work and begin drain mode
3. wait for in-flight requests or sessions to drain
4. shut down listeners
5. wait for all tracked connections/goroutines to exit
6. then terminate the process

If the service handles long-lived connections, track active sessions explicitly
with a counter or registry so shutdown can verify that the system actually
drained before exiting.

---

## Mutex vs Atomic Decisions

### 1. Use `sync.Mutex` for Complex State

When protecting a struct with multiple fields or coordinating non-trivial
operations, use a mutex.

```go
type Runner struct {
    mu      sync.Mutex
    started bool      // mu protects started
    count   int       // mu protects count
    last    time.Time // mu protects last
}

func (r *Runner) RecordRun() {
    r.mu.Lock()
    defer r.mu.Unlock()
    r.count++
    r.last = time.Now()
}
```

Document which fields are protected. The comment `// mu protects X` is the
standard convention.

---

### 2. Use `sync/atomic` for Simple Counters and Flags

For a single counter or boolean flag, atomic operations are lighter and
avoid lock contention.

```go
type Server struct {
    healthy atomic.Bool   // set by health checker
    reqCount atomic.Int64 // incremented per request
}

func (s *Server) Handle(ctx context.Context, req *Request) {
    s.reqCount.Add(1)
    // ...
}

func (s *Server) IsHealthy() bool {
    return s.healthy.Load()
}
```

Go 1.19+ `atomic.Bool`, `atomic.Int64`, etc. are preferred over
`atomic.LoadInt64` / `atomic.StoreInt64` on raw fields.

---

### 3. Prefer `sync.RWMutex` When Reads Dominate Writes

If most accesses are reads and writes are infrequent, `RWMutex` reduces
contention.

```go
type Registry struct {
    mu    sync.RWMutex
    items map[string]*Entry // mu protects items
}

func (r *Registry) Get(key string) (*Entry, bool) {
    r.mu.RLock()
    defer r.mu.RUnlock()
    e, ok := r.items[key]
    return e, ok
}

func (r *Registry) Set(key string, entry *Entry) {
    r.mu.Lock()
    defer r.mu.Unlock()
    r.items[key] = entry
}
```

---

## Channel Patterns

### 1. Prefer `select` with `ctx.Done()` for Blocking Operations

Never block on a channel without a cancellation escape hatch.

Good:

```go
func (w *Worker) Run(ctx context.Context) error {
    for {
        select {
        case <-ctx.Done():
            return ctx.Err()
        case job, ok := <-w.jobs:
            if !ok {
                return nil // channel closed
            }
            w.handle(ctx, job)
        }
    }
}
```

Bad:

```go
func (w *Worker) Run() {
    for job := range w.jobs { // blocks forever if jobs is never closed
        w.handle(context.Background(), job)
    }
}
```

Use `time.After` for timeouts:

```go
select {
case <-ctx.Done():
    return ctx.Err()
case <-time.After(5 * time.Second):
    return errors.New("timeout")
case job := <-w.jobs:
    w.handle(ctx, job)
}
```

---

### 2. Prefer Unbuffered Channels by Default

Start with unbuffered channels unless you have a specific, measured reason to
add a buffer.

Unbuffered channels make handoff and backpressure explicit. Buffers often just
hide architectural bottlenecks, introduce bursty behavior, or mask shutdown and
coordination bugs that should be fixed directly.

Buffered channels are appropriate when:

- the producer/consumer rate mismatch is intentional and understood
- the queue length is part of the design
- benchmarks or production measurements show a real improvement

If you add a channel buffer, document why that capacity exists.

---

### 3. Close Channels from the Sender Side Only

The sender owns the channel lifecycle. Closing from the receiver causes
panics if the sender writes after close.

Good:

```go
func (p *Producer) Run(ctx context.Context) {
    defer close(p.out) // sender closes
    for {
        select {
        case <-ctx.Done():
            return
        default:
            val, err := p.generate(ctx)
            if err != nil {
                return
            }
            p.out <- val
        }
    }
}
```

Bad:

```go
func (c *Consumer) Stop() {
    close(c.in) // ❌ receiver closing sender's channel
}
```

---

### 4. Document Channel Ownership and Lifecycle

When a struct holds channels, document who creates, writes, reads, and
closes them.

```go
type Pipeline struct {
    // jobs is written by Enqueue and read by worker goroutines.
    // Closed by Close() to signal workers to drain and exit.
    jobs chan *Task

    // results is written by workers and read by the caller via Results().
    // Closed when all workers finish.
    results chan *Result
}
```

Undocumented channels in structs are a review blocker.

---

## `-race` Is Not Optional

**If it's not tested with `-race`, it's broken.**

The race detector finds real shared-memory bugs that code review and normal test
runs routinely miss. Treat it as a required part of concurrency verification,
not an optional extra.

Run:

```sh
go test -race ./...
```

If a package uses goroutines, shared mutable state, background workers, or
connection management, it should be assumed unsafe until it passes `-race`.

---

## Common Concurrency Pitfalls

### 1. Goroutine Leaks from Missing Cancellation

The most common concurrency bug. A goroutine blocks on a channel or I/O
call with no context, and it never exits.

Leaky:

```go
func (w *Worker) Start() {
    go func() {
        resp, err := http.Get(w.url) // blocks forever on slow server
        if err != nil {
            return
        }
        w.handle(resp)
    }()
}
```

Fixed:

```go
func (w *Worker) Start(ctx context.Context) {
    go func() {
        req, err := http.NewRequestWithContext(ctx, http.MethodGet, w.url, nil)
        if err != nil {
            return
        }
        resp, err := http.DefaultClient.Do(req)
        if err != nil {
            return
        }
        defer resp.Body.Close()
        w.handle(resp)
    }()
}
```

---

### 2. Data Races from Shared Mutable State

If two goroutines touch the same field without synchronization, you have a
data race. The `-race` detector will find it. Run it.

Racy:

```go
type Counter struct {
    n int
}

func (c *Counter) Inc() { c.n++ }      // ❌ no synchronization
func (c *Counter) Get() int { return c.n }
```

Fixed:

```go
type Counter struct {
    n atomic.Int64
}

func (c *Counter) Inc() { c.n.Add(1) }
func (c *Counter) Get() int64 { return c.n.Load() }
```

---

### 3. Deadlocks from Inconsistent Lock Ordering

When multiple mutexes are involved, always acquire them in the same order.
Document the ordering.

Deadlock-prone:

```go
// Goroutine 1: locks A then B
a.mu.Lock()
b.mu.Lock()

// Goroutine 2: locks B then A
b.mu.Lock()
a.mu.Lock()
```

If your code requires multiple locks, document the required acquisition
order at the type level:

```go
type Coordinator struct {
    // Lock ordering: always acquire mu before acquiring pool.mu.
    mu   sync.Mutex
    pool *Pool
}
```

When possible, redesign to eliminate the need for multiple locks.

---

## What Not To Do

### Do not spawn goroutines without tracking them

```go
// ❌ Avoid
go doWork()
```

Every goroutine must be reachable by cancellation or tracked by a
`sync.WaitGroup`.

### Do not use `context.Background()` in place of proper propagation

```go
// ❌ Avoid
go func() {
    resp, err := client.Do(ctx, req) // ← but ctx is from where?
    // ...
}()
```

Pass the caller's context explicitly through every layer.

### Do not store `context.Context` in a struct field

```go
// ❌ Avoid
type Handler struct {
    ctx context.Context
}
```

Contexts are per-call, not per-instance.

### Do not close channels from the receiver

```go
// ❌ Avoid — panics if sender writes after close
close(incomingCh)
```

The sender owns the close.

### Do not ignore the `-race` detector

```sh
go test -race ./...
```

If you are not running `-race` in CI, you are not testing concurrency.

---

## Summary

- Every goroutine must have a clear shutdown path via `context.Context` or channel close.
- Accept `context.Context` as the first parameter; never store it in structs.
- Long-lived services implement `Close()` or `Stop()` backed by `sync.WaitGroup`.
- Add jitter to recurring background work when synchronized schedules would create spikes.
- Use `sync.Mutex` for complex state; use `sync/atomic` for simple counters and flags.
- Prefer `sync.RWMutex` when reads vastly outnumber writes.
- Document synchronization intent on every guarded struct field.
- Use context-aware I/O APIs such as `QueryContext` and `NewRequestWithContext`.
- Prefer unbuffered channels unless a measured design need justifies buffering.
- Close channels from the sender side only; document ownership.
- Always run `go test -race ./...` in CI.
- Graceful shutdown should fail readiness, drain in-flight work, stop listeners, and wait for tracked work to finish.
- Fire-and-forget goroutines require explicit justification in comments.

---

## Guiding Rule

**If you start a goroutine, you own its lifecycle. If you share state, you document its synchronization.**
