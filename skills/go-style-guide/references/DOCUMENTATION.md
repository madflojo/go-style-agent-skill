# Documentation + Comments

Documentation is part of code readability, not post-hoc decoration.

This reference defines how to write durable, idiomatic Go documentation for both
public APIs and important internal code.

---

## Package docs

Packages that expose reusable behavior should have a package comment.

Package docs should use the `/** ... */` block comment form:

```go
/**
Package cache provides a TTL-aware in-memory key-value store.

The primary entrypoint is New, which returns a *Cache configured
with the provided Config. Cache is safe for concurrent use.

Expired entries are removed lazily on access and periodically by
a background goroutine. Call Close to stop background cleanup.
*/
package cache
```

Package docs should explain:

- what the package provides
- the main entrypoints or responsibilities
- notable behavior, constraints, or lifecycle expectations

Keep package docs factual and short.

Good:

```go
/**
Package cache provides a TTL-aware in-memory key-value store.

The primary entrypoint is New, which returns a *Cache configured
with the provided Config. Cache is safe for concurrent use.

Expired entries are removed lazily on access and periodically by
a background goroutine. Call Close to stop background cleanup.
*/
package cache
```

Bad:

```go
/** Package cache provides cache functionality. */
package cache
```

A package comment that restates the package name tells readers nothing.
Explain purpose, entrypoints, and operational constraints so the reader
knows what they are importing.

---

## Idiomatic godoc

Doc comments should follow normal Go conventions:

- use `//` line comments for functions, methods, types, vars, consts, fields,
  and other non-package declarations
- start with the identifier name
- use complete sentences
- describe behavior, contracts, and relevant caveats
- prefer durable wording over implementation chatter

Good:

```go
// New validates Config, applies defaults, and returns a Worker.
func New(cfg Config) (*Worker, error) { ... }
```

Avoid:

```go
// New creates a new Worker.
func New(cfg Config) (*Worker, error) { ... }
```

When relevant, docs should mention:

- defaults and zero-value behavior
- nil handling
- concurrency or blocking behavior
- ownership and lifecycle expectations
- stable error semantics callers may branch on

In modern Go versions, doc comments can link to identifiers with brackets such
as `[Config]`, `[New]`, or `[Worker.Run]`. Use these links when they improve
navigation or clarify relationships, especially in package docs and constructor
comments.

### Config struct doc comments

Good:

```go
// Config controls Server construction and runtime behavior.
// A zero-value Config is not valid; at minimum Addr must be set.
// New copies Config into Server; later field changes do not affect the server.
// Nil Logger disables request logging.
type Config struct {
    // Required: listen address.
    Addr    string

    // Optional: nil disables request logging.
    Logger  *slog.Logger

    // Optional: defaults to DefaultTimeout.
    Timeout time.Duration
}
```

Bad:

```go
// Config is the config for Server.
type Config struct {
    Addr    string
    Logger  *slog.Logger
    Timeout time.Duration
}
```

Config types appear in every constructor call. Their doc comment should
explain validity constraints and zero-value behavior, not restate the
type name. Field comments can also mark `Required` versus `Optional` inputs
when that makes construction rules easier to scan.

### Interface method doc comments

Good:

```go
// Store defines durable key-value persistence.
type Store interface {
    // Get retrieves the value for key. Returns ErrNotFound if the
    // key does not exist. The returned slice must not be modified
    // by the caller.
    Get(ctx context.Context, key string) ([]byte, error)

    // Put writes value under key, overwriting any previous entry.
    // A nil value deletes the key.
    Put(ctx context.Context, key string, value []byte) error
}
```

Bad:

```go
type Store interface {
    // Get gets a value.
    Get(ctx context.Context, key string) ([]byte, error)

    // Put puts a value.
    Put(ctx context.Context, key string, value []byte) error
}
```

Interface methods are the contract. Each method comment should document
error semantics, ownership of returned data, and side effects so that
both implementors and callers share the same expectations.

### Constant group doc comments

Good:

```go
// Default limits applied when Config fields are zero.
const (
    DefaultTimeout  = 30 * time.Second
    DefaultMaxRetry = 3
    DefaultPoolSize = 10
)
```

Bad:

```go
const (
    DefaultTimeout  = 30 * time.Second
    DefaultMaxRetry = 3
    DefaultPoolSize = 10
)
```

A group-level comment explains why the constants exist and when they
take effect. Without it, the reader must trace call sites to understand
the relationship between these values.

---

## Example functions

Use `Example_` functions in `_test.go` files to document the intended public
usage of a package, type, or function.

These examples are the gold standard for Go documentation because they:

- are verified by `go test`
- stay close to the API they demonstrate
- render cleanly in godoc/pkg.go.dev

Good:

```go
func ExampleNew() {
    worker, err := New(Config{Name: "jobs"})
    if err != nil {
        panic(err)
    }

    fmt.Println(worker.Name())
    // Output: jobs
}
```

Prefer examples for:

- happy-path package usage
- constructor setup with realistic `Config`
- small workflows that are easier to understand from code than prose

If an exported API is important enough to teach, it is often important enough to
have an example.

---

## Deprecation comments

When a public symbol should no longer be used, mark it with the standard Go
format:

```go
// Deprecated: use NewClient instead.
func New() *Client { ... }
```

Use the exact `Deprecated:` prefix. Tooling recognizes this format and surfaces
it in editors and generated documentation.

Keep deprecation comments short and actionable:

- say what to use instead when possible
- keep the old symbol behavior stable while it remains exported
- avoid long migration essays in the comment itself

---

## Internal functions

Internal functions deserve documentation when they are part of the package's
mental model or hide non-obvious behavior.

Strong default:

- document helpers that coordinate important flow
- document side effects, invariants, and ordering assumptions
- document non-obvious why, not obvious mechanics

Trivial wrappers and obvious one-liners do not need forced comments.

Good:

```go
// drainQueue processes remaining items before shutdown.
// It must be called with mu held. The caller is responsible
// for signaling done after drainQueue returns.
func (s *Server) drainQueue() {
    for len(s.queue) > 0 {
        s.process(s.queue[0])
        s.queue = s.queue[1:]
    }
}
```

Bad:

```go
// drainQueue drains the queue.
func (s *Server) drainQueue() {
    for len(s.queue) > 0 {
        s.process(s.queue[0])
        s.queue = s.queue[1:]
    }
}
```

The good version explains the locking invariant and caller responsibility.
The bad version adds a comment that says nothing the name did not already
convey. If there is nothing non-obvious to say, leave the function
uncommented rather than forcing a noise comment.

---

## Struct fields

Document struct fields, even when unexported, when the field helps a reader
understand:

- role or responsibility
- lifecycle or ownership
- synchronization expectations
- caching or buffering behavior
- invariants that names alone do not make obvious

This is especially useful for:

- `Config` structs
- long-lived runtime structs
- structs with goroutines, mutexes, caches, or background state

Good:

```go
// Server handles incoming connections and dispatches work.
type Server struct {
    // listener accepts incoming connections. Owned by Serve;
    // closed on Shutdown.
    listener net.Listener

    // mu guards handler and closed. Held briefly during
    // registration and shutdown.
    mu      sync.Mutex
    handler Handler
    closed  bool

    // wg tracks in-flight requests. Shutdown blocks until
    // wg reaches zero.
    wg sync.WaitGroup
}
```

Bad:

```go
type Server struct {
    listener net.Listener // listener
    mu       sync.Mutex
    handler  Handler
    closed   bool
    wg       sync.WaitGroup
}
```

The good version documents ownership, synchronization scope, and shutdown
semantics. A reader can understand the struct's concurrency model without
reading every method. The bad version either restates the name or leaves
the reader guessing.

---

## Package globals

Document package-level globals, vars, and consts when their purpose or behavior
is not trivial.

Call out:

- whether the value is mutable
- synchronization expectations
- lifecycle or initialization assumptions
- why the value exists at package scope

Mutable package globals should be rare. If they exist, their comment should make
the tradeoff obvious.

Good:

```go
// defaultTransport is the shared HTTP transport for all Clients
// created without an explicit Transport in Config. It is
// initialized once and must not be modified after package init.
var defaultTransport = &http.Transport{
    MaxIdleConns:    100,
    IdleConnTimeout: 90 * time.Second,
}
```

Bad:

```go
var defaultTransport = &http.Transport{
    MaxIdleConns:    100,
    IdleConnTimeout: 90 * time.Second,
}
```

An undocumented mutable global forces every reader to audit the codebase
for writes. A one-sentence comment explaining mutability and scope prevents
that entirely.

---

## Summary

- Every exported symbol needs a doc comment starting with its name.
- Package comments explain purpose, entrypoints, and constraints.
- Doc comments describe behavior and contracts, not implementation.
- Use bracket links like `[Config]` when they improve godoc navigation.
- Config struct docs state validity rules and zero-value behavior.
- Interface method docs specify error semantics, ownership, and side effects.
- Constant groups get a group-level comment explaining when values apply.
- Use `Example_` functions for important public usage; they are executable docs.
- Mark deprecated public symbols with `// Deprecated: use X instead.`
- Internal functions earn comments when they hold invariants or hide non-obvious behavior.
- Struct fields document lifecycle, ownership, and synchronization.
- Package globals document mutability and sync expectations.
- Comments must outlive the change that introduced them — no agent context, no temporary notes.

---

## Durable comments only

Comments should survive code generation and remain useful to future readers.

Do not add:

- agent-context comments
- self-referential TODO/FIXME notes
- comments that describe how an agent plans to revisit code later
- temporary notes that do not improve readability

Avoid:

```go
// TODO(agent): clean this up later.
// This helper exists because the model generated the code in phases.
```

Prefer comments that explain intent, contracts, and non-obvious design choices.

---

## Guiding Rule

**Documentation should outlive the code change that introduced it.**
