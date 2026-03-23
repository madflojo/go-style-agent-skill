# Configuration + Constructors (Config Struct Pattern)

In this style guide, **configuration is explicit**.

Packages should be constructed with a clear `Config` struct, apply defaults
predictably, validate inputs early, and return a concrete runtime object.

This pattern works well in Go codebases that value clarity, explicit construction, and testability.

---

## Core Principles

The `Config` struct should tell users exactly how to control the behavior of
your package or service.

### 1. Prefer `Config` Structs Over Functional Options

Functional options have a place, especially in legacy or ecosystem-driven APIs.

But new code should default to:

- `Config` in
- defaults applied explicitly
- validation at construction
- concrete struct returned

```go
cfg := Config{
    Namespace: "example-service",
}

c, err := New(cfg)
```

This is clearer for:

- humans
- coding agents
- test scenarios
- long-lived maintenance

---

### 2. Constructors Must Be Explicit

Preferred constructor forms:

- `New(cfg Config) (*T, error)`
- `Dial(cfg Config) (*T, error)`

Constructors should:

- validate required fields
- apply defaults
- return sentinel errors

For small configs, keeping validation inline in `New` is fine. For larger or
more nested configs, move the checks into a dedicated
`func (c *Config) Validate() error` method so the constructor does not become a
long block of unrelated validation logic.

Prefer passing `Config` by value unless the struct is exceptionally large or
contains fields that make copying unsafe. A value parameter makes ownership
clearer and prevents callers from mutating shared config state after
construction.

Avoid `init()` for normal package setup. Construction should happen through
explicit `New`/`Dial` paths so dependencies, defaults, and side effects are
visible to callers and test code.

---

## Canonical Pattern

### Example: Generic Executor

This is the preferred shape:

```go
// Runner is a minimal dependency for executing work.
type Runner interface {
    Run(ctx context.Context, input []byte) ([]byte, error)
}

// Config configures executor behavior and dependencies.
type Config struct {
    Timeout time.Duration

    // Runner allows injection for tests.
    Runner Runner
}

// Executor is the concrete implementation.
type Executor struct {
    cfg  Config
    run  Runner
}
```

Key takeaways:

- Dependency interface is boundary-driven (`Runner`)
- Config is explicit and documented
- Concrete struct holds runtime behavior

---

## Constructor Rules

### Apply Defaults Explicitly

Do not rely on implicit zero-value magic when defaults matter.

```go
func New(cfg Config) (*Executor, error) {
    if cfg.Timeout == 0 {
        cfg.Timeout = DefaultTimeout
    }

    if cfg.Runner == nil {
        cfg.Runner = DefaultRunner
    }

    return &Executor{
        cfg:  cfg,
        run: cfg.Runner,
    }, nil
}
```

Defaults must be:

- visible
- documented
- stable

Treat the constructor-normalized config as immutable state. Once `New` returns,
the constructed object should rely on its own copied config or extracted fields,
not on future caller-side field mutations. If behavior must change at runtime,
expose an explicit method for that change instead of expecting callers to mutate
`Config`.

### Make Important Runtime Knobs Explicit

Critical operational behavior should not hide behind dangerous library or
runtime defaults.

When a package owns external I/O or background work, make important knobs
explicit in `Config` and document their defaults:

- request and dial timeouts
- idle timeouts
- connection max lifetime / idle lifetime
- pool sizes
- retry ceilings and backoff settings

These settings do not usually cause incidents by themselves, but they often
determine whether an incident becomes survivable or catastrophic.

---

### Validate Early (Fail Fast)

Invalid config should fail in `New`, not later.

```go
var ErrInvalidConfig = errors.New("invalid config")

func New(cfg Config) (*Executor, error) {
    if cfg.Runner == nil {
        return nil, ErrInvalidConfig
    }

    return &Executor{cfg: cfg}, nil
}
```

When validation logic is substantial, prefer a dedicated method:

```go
func (c *Config) Validate() error {
    if c.Runner == nil {
        return ErrInvalidConfig
    }
    if c.Timeout < 0 {
        return fmt.Errorf("%w: timeout must be non-negative", ErrInvalidConfig)
    }
    return nil
}

func New(cfg Config) (*Executor, error) {
    if cfg.Timeout == 0 {
        cfg.Timeout = DefaultTimeout
    }
    if err := cfg.Validate(); err != nil {
        return nil, err
    }
    return &Executor{cfg: cfg}, nil
}
```

The rule is not "always extract validation." The rule is "keep `New` readable".
If the constructor starts mixing defaults, dependency wiring, validation, and
runtime setup into one long function, extract `Validate()` and keep the
constructor focused on assembly.

---

### Return Concrete Types Unless Interface Return Is Required

Preferred:

```go
func New(cfg Config) (*ExecutorImpl, error)
```

Interface returns are useful when:

- multiple implementations exist
- drivers are swapped dynamically
- mocking is part of the API contract

Avoid returning interfaces "just because."

---

## Config Ownership Rules

### Packages Own Their Own Config

Do not pass global application config everywhere.

Bad:

```go
func New(v *viper.Viper) *Server
```

Good:

```go
type Config struct {
    Addr string
    Timeout time.Duration
}

func New(cfg Config) (*Server, error)
```

Config should be:

- local
- typed
- testable

---

### Avoid Config Coupling Between Packages

Do not inject another package's Config struct directly unless unavoidable.

Bad:

```go
func Dial(log *logger.Logger, cfg *config.Config)
```

Better:

```go
type Config struct {
    Addr string
    Password string
}
```

Push only what you need.

---

## Config Struct Layout

Config fields should be:

- grouped logically
- documented
- ordered for readability

Example:

```go
type Config struct {
    // Required: identity / namespace.
    Namespace string

    // Optional: defaults to DefaultTimeout.
    Timeout time.Duration

    // Optional: defaults to DefaultMaxSize.
    MaxSize int

    // Optional: nil disables package logging.
    Logger *slog.Logger

    // Optional: defaults to net.Dialer.
    Dialer DialFunc
}
```

Use short field comments when it helps make required vs optional inputs obvious,
especially when defaults or zero-value behavior are not immediately clear.

---

## Logging Injection Exception

Packages should not log by default.

If logging is truly required (async TCP, gRPC internals), then:

- inject via Config
- use `*slog.Logger`
- document it as an exception

```go
type Config struct {
    Logger *slog.Logger
}
```

---

## Operational Controls and Degraded Modes

In critical services, it is sometimes worth designing explicit operator
controls for non-essential behavior.

Examples:

- disable event publishing during downstream brownouts
- pause optional cache warming or background enrichment
- bypass a non-critical dependency while the core path stays available

These are not a substitute for good design, and they should not be scattered as
ad hoc booleans throughout the codebase.

Prefer one of these patterns:

- a clearly named field in `Config` for construction-time policy
- an injected control interface for runtime decisions
- explicit methods on long-lived service structs for entering/exiting degraded modes

Keep the names behavior-oriented, such as `PublishingEnabled` or
`AllowFallback`, rather than vague flags like `DisableStuff`.

If behavior must change at runtime, do not ask callers to mutate `Config` after
construction. Use explicit runtime controls instead.

---

## Testability Benefits

Config structs make testing easy:

```go
type failingRunner struct{}

func (f failingRunner) Run(ctx context.Context, input []byte) ([]byte, error) {
    return nil, errors.New("boom")
}

func TestExecutorTimeout(t *testing.T) {
    e, err := New(Config{
        Timeout: 10 * time.Millisecond,
        Runner:  failingRunner{},
    })
    if err != nil {
        t.Fatalf("New() unexpected error: %v", err)
    }

    _, err = e.Run(context.Background(), nil)
    if err == nil {
        t.Fatal("Run() expected error, got nil")
    }
}
```

This is one of the main reasons Config-first design is preferred.

---

## Summary Rules

- Config struct is the default contract
- Defaults must be explicit
- Important runtime knobs must be visible and documented
- Validate early, fail fast
- Use `Config.Validate()` when config validation becomes non-trivial
- Prefer `Config` parameters by value
- Treat constructor-normalized config as immutable internal state
- Return concrete structs unless interface return is required
- Config belongs to the package, not the app
- Inject boundaries through Config for testability
- Critical services may need explicit operational controls or degraded modes
- `*slog.Logger` is the standard logging injection type

---

## Guiding Rule

**Configuration should make behavior obvious at construction time and show
users exactly how to control package behavior.**
