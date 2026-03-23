# Layout (File and Package Organization)

This reference defines how to organize Go code for **readability**, **maintainability**, and
**runtime efficiency**.

## Table of Contents

- [Goals](#goals)
- [Directory layout guidance](#directory-layout-guidance)
- [Package boundaries](#package-boundaries)
- [File naming](#file-naming)
- [In-file ordering](#in-file-ordering)
- [Documentation](#documentation)
- [Interfaces and testability](#interfaces-and-testability)
- [Struct field layout and efficiency](#struct-field-layout-and-efficiency)
- [Receiver naming](#receiver-naming)
- [Export discipline](#export-discipline)
- [Tests and benchmarks](#tests-and-benchmarks)
- [Main package layout](#main-package-layout)
- [When to split files or packages](#when-to-split-files-or-packages)
- [Summary checklist](#summary-checklist)

---

It applies to:

- standalone libraries
- backend services
- hybrid runtimes and SDK-style projects

The goal is to guide both **humans** and **coding agents** toward consistent, idiomatic Go
structure.

---

## Goals

1. **Scanability**
   A reader should understand the shape of a package in seconds.

2. **Testability-first design**
   Packages should be independently testable with clear seams.

3. **Efficiency where it matters**
   Hot-path types and struct layouts should be intentional.

4. **Predictability**
   Consistent conventions reduce cognitive load and agent drift.

---

## Directory layout guidance

### Standalone libraries

For a library repository:

- keep packages shallow
- avoid unnecessary nesting
- avoid `internal/` unless you truly need enforcement

Example:

```text
.
├── go.mod
├── README.md
├── worker.go
├── config.go
├── drivers/
│   ├── file/
│   └── memory/
└── docs/
```

Library repos already define a boundary.
Over-structuring usually adds friction.

---

### Services / applications

For backend services and apps:

- entrypoints live in `cmd/`
- this guide prefers grouping service packages under `pkg/` for clarity
- runtime orchestration often lives in `pkg/app`

This is a house preference for service repos, not an idiomatic law:

> If a service repo adopts `pkg/`, keep the non-`main` packages there consistently.

Many solid Go services keep packages at the repo root, use `internal/`, or mix
top-level and `internal/` packages intentionally. If a repository already has a
clear convention, follow that convention rather than forcing `pkg/`.

Do not restructure an existing repository to introduce `pkg/` unless you were
explicitly asked to make that migration. Follow whatever layout the repository
already uses.

If a repo already uses `internal/`, keep using it to conform to the repository's
existing visibility and package-boundary rules.

Example:

```text
.
├── cmd/
│   └── myapp/
│       └── main.go
├── pkg/
│   ├── app/          # runtime orchestration + lifecycle
│   ├── config/       # config parsing + validation
│   ├── database/     # external system boundaries
│   ├── worker/       # capability-focused package
│   └── telemetry/    # metrics/tracing/logging wiring
└── README.md
```

Rule of thumb:

- `cmd/` = startup + user-facing wiring only
- `pkg/app` = dependency coordination + lifecycle when this repo shape is used
- `pkg/*` = domain-focused packages when this repo shape is used

---

## Package boundaries

### Prefer domain packages over buckets

Good:

- `pkg/worker`
- `pkg/tlsconfig`
- `pkg/cache/lookaside`

Avoid:

- `pkg/utils`
- `pkg/common`
- `pkg/helpers`

Generic buckets become junk drawers and reduce clarity.

### Architectural guardrails should make the right path easy

Do not rely on future readers remembering the original design intent.
Package boundaries, contracts, and entry points should act as guardrails.

Good guardrails:

- clear ingress/egress packages
- narrow contract packages at real boundaries
- explicit ownership of orchestration in `app/`
- domain packages that make misplaced functionality feel obviously wrong

The goal is not to make change hard.
The goal is to make the correct placement of change the path of least
resistance.

If the architecture depends on everyone remembering a document from six months
ago, the structure is too weak.

---

## File naming

### Prefer domain file names over catch-alls

Good:

- `request.go`
- `response.go`
- `retry.go`

Avoid:

- `types.go`
- `constants.go`
- `util.go`

If a file becomes "mixed," it's often a signal the package boundary is wrong.

Also avoid file names that collide with common standard-library package names,
such as `os.go`, `context.go`, `http.go`, or `json.go`, unless the package is
actually about that domain. These names can make imports, stack traces, editor
search, and discussion more confusing than necessary.

---

### Primary file convention

A package's main exported surface often lives in a file matching the package name:

- `config/config.go`
- `database/database.go`
- `pkg/kvstore/kvstore.go`

This improves navigation.

---

## In-file ordering

Files should follow idiomatic Go structure and be predictable.

Recommended ordering:

1. Package docs + `package x`
2. Imports
3. Constants and vars
4. Sentinel errors
5. Exported types
6. Interfaces
7. Config structs
8. Constructors
9. Exported functions/methods
10. Unexported helpers

Avoid `init()` unless absolutely required.
In general, `init()` is a smell: it often hides globals, ordering dependencies,
implicit registration, or startup side effects that are clearer and safer when
made explicit through constructors or setup functions.

Narrow exceptions exist for package-level registration or truly unavoidable
runtime wiring, but they should be rare and easy to justify in review.

---

### Example skeleton

```go
// Package worker provides task execution via an injected Runner.
package worker

import (
    "context"
    "errors"
    "time"
)

// Exported constants.
const DefaultTimeout = 3 * time.Second

// Sentinel errors.
var (
    ErrInvalidConfig = errors.New("worker: invalid config")
    ErrRunFailed     = errors.New("worker: run failed")
)

// Boundary interface.
type Runner interface {
    Run(ctx context.Context, input []byte) ([]byte, error)
}

// Config defines construction-time behavior.
type Config struct {
    Timeout time.Duration
    Runner Runner
}

// New validates config, applies defaults, and returns a concrete Worker.
func New(cfg Config) (*Worker, error) {
    if cfg.Timeout == 0 {
        cfg.Timeout = DefaultTimeout
    }
    if cfg.Runner == nil {
        return nil, ErrInvalidConfig
    }

    return &Worker{cfg: cfg}, nil
}

// Worker implements Runner-backed task execution.
type Worker struct {
    cfg Config
}
```

---

## Documentation

Documentation and comment-style guidance lives in `DOCUMENTATION.md`.

Use it for:

- package docs and idiomatic godoc expectations
- internal function comments
- struct field documentation
- package globals
- durable comment rules for humans and agents

---

## Interfaces and testability

Interfaces are a tool for **testability and boundary isolation**.

### Interfaces belong at boundaries

Good uses:

- database drivers
- transport injection
- network transports
- external service clients

Avoid interfaces purely for abstraction layering.

As a default, the consumer defines the small interface it needs and the producer
exports a concrete type. When a package is intentionally a shared boundary
package, that package can own the interface plus shared errors and constants.

Example:

```text
pkg/
└── kvstore/
    ├── kvstore.go         # interface, errors, constants
    └── drivers/
        ├── memory/
        ├── file/
        └── mock/
```

This pattern is appropriate when `pkg/kvstore` is the contract package and the
driver subpackages are implementation details selected by the app or tests.

---

### Constructors should usually return concrete types

Prefer:

```go
func New(cfg Config) (*Worker, error)
```

Not:

```go
func New(cfg Config) (Worker, error)
```

Returning interfaces can hide behavior and complicate extension.

Exception:

- when the package's primary purpose is a driver interface
- when multiple implementations are expected immediately

Testability is still achieved through injected dependencies and boundary interfaces.

---

## Struct field layout and efficiency

### Field ordering matters in hot paths

Struct layout affects:

- padding
- cache locality
- allocation behavior

Guidelines:

1. Group by alignment size (largest → smallest)
2. Keep hot fields close together
3. Optimize hot-path structs more than config structs

Example:

Bad:

```go
type Stats struct {
    ok    bool
    count uint64
    name  string
    err   error
}
```

Better:

```go
type Stats struct {
    count uint64
    err   error
    name  string
    ok    bool
}
```

Do not over-optimize config structs.
Optimize where benchmarks justify it.

---

## Receiver naming

Receivers should be short and consistent:

- `e *Executor`
- `w *Worker`
- `s *Server`
- `db *Database`
- `r *Router`

Avoid verbose receiver names.

---

## Export discipline

- Export only what users need.
- Prefer unexported fields/methods.
- Exported struct fields are acceptable for JSON/YAML boundaries.

---

## Tests and benchmarks

Testing conventions and patterns live in `TESTING.md`.

### Tests

- Prefer table-driven tests for behavior matrices
- Use subtests with clear names
- Apply `t.Parallel()` when safe

Example:

```go
func TestWorker_Run(t *testing.T) {
    tests := []struct {
        name string
        input  []byte
        wantErr error
    }{...}

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            t.Parallel()
            ...
        })
    }
}
```

---

### Benchmarks

Hot paths should have benchmarks.

- report allocations
- use realistic inputs
- track trends over time

Naming:

- `BenchmarkNew`
- `BenchmarkDo_SmallPayload`
- `BenchmarkDo_LargePayload`

---

## Module and dependency hygiene

Keep `go.mod` and `go.sum` intentional. Dependency drift makes repositories
harder to review and harder for agents to change safely.

Rules:

- keep the `go` version aligned with the repository's actual supported baseline
- run `go mod tidy` after adding, removing, or renaming imports
- do not add a dependency for convenience when the standard library is already sufficient
- prefer small, focused dependencies over broad utility bundles
- review indirect dependency churn instead of assuming it is harmless

Remember that Go uses Minimal Version Selection (MVS). Adding one module can
raise the selected version of another, so dependency changes deserve the same
review attention as code changes.

If a change adds a dependency, be able to explain:

- why the dependency is necessary
- why an existing dependency or the standard library is not enough
- whether the dependency affects startup time, binary size, or transitive risk

Treat `go mod tidy` output as part of the change, not background noise.

---

## Main package layout

Main should do only:

- argument/env parsing
- config load
- dependency wiring
- app start + shutdown

Main should not contain core business logic.

Example flow:

```text
cmd/myapp/main.go
  -> load config
  -> app.New(cfg)
  -> app.Run(ctx)
```

Where:

```go
import "myapp/pkg/app"
```

---

## When to split files or packages

Split a file when:

- it exceeds ~300–400 lines
- it becomes hard to scan

Split a package when:

- it becomes a god package
- tests require booting unrelated systems
- multiple domains are mixed

---

## Summary checklist

- [ ] Packages are domain-focused, not buckets
- [ ] No `utils/` or `common/`
- [ ] File ordering is predictable
- [ ] Interfaces improve testability at boundaries
- [ ] Struct layout is efficient in hot paths
- [ ] Tests are table-driven where useful
- [ ] Benchmarks exist for performance-sensitive code
- [ ] `cmd/` is thin, `pkg/app` orchestrates runtime
