---
name: go-style-guide
description: >
  Go engineering style guide for designing packages, services, and CLIs.
  Use for new Go code, refactors, reviews, API design, error and logging
  patterns, config and constructor decisions, testing, and benchmarks.
license: Apache-2.0
metadata:
  author: "Benjamin Cane"
  version: "0.1"
---

# Go Style Guide Skill

This skill defines practical Go engineering conventions optimized for:

- **humans** reading and maintaining code
- **coding agents** generating or refactoring code reliably
- **production readiness** (correctness, testability, performance)

Use this skill whenever you are working with Go: new code, refactors,
reviews, and architecture decisions.

---

## TL;DR

- Design for testability first; inject dependencies and keep logic pure.
- Prefer `Config` in → concrete struct out; validate, default, and document important runtime knobs.
- Errors are contracts: use sentinels for durable branching; wrap the rest with `%w` or `errors.Join`.
- Keep packages reusable: no hidden globals, no default logging, no surprise side effects.
- Coverage is a signal, not proof; test edge cases and misuse paths, not just happy paths.
- Follow "accept interfaces, return structs"; consumers usually define interfaces, shared contract packages are a special case.
- Keep `main.go` thin; follow existing repo layout conventions rather than forcing one directory shape.
- Benchmark hot paths before claiming wins, and run concurrency code with `-race`.
- Maintain contracts such as function signatures, config shape, error behavior, and doc comments; they are as important as the code itself.

---

## House Style Disclaimer

This is intentionally opinionated. It favors consistency and long-term
maintainability over accommodating every Go style preference.

---

## Compatibility

Examples assume modern Go and use standard-library features such as
`errors.Join` and `log/slog`. Apply the guide within the constraints of the
target repository's supported Go version.

---

## Execution Protocol

Follow this workflow when using the skill for implementation work:

1. Inspect the repository first.
   Read existing package layout, constructors, tests, and error conventions
   before proposing new APIs or moving files.

2. Define the contract before coding.
   Decide the package boundary, config shape, concrete return type, sentinel
   errors, and context or shutdown expectations up front.

3. Write or update tests early when practical.
   Start with table-driven unit tests, add fuzz tests for parsing or other
   input-heavy code, and add benchmarks for performance-sensitive paths.

4. Implement the smallest maintainable change.
   Follow the repository's existing layout, keep `main.go` thin, and avoid
   introducing new abstractions without a clear boundary.

5. Run the finishing checks.
   Format with `gofmt` (and `goimports` if the repo uses it), run the relevant
   `go test` targets, run `go test -race` when concurrency is involved, and run
   benchmarks when claiming performance improvements.

6. Verify the human-facing contract.
   Make sure docs, comments, config defaults, and error behavior match the code
   you are shipping.

---

## Quick Rules Table

| Topic | Rule | Reference |
| --- | --- | --- |
| Testability | Design for confidence, not coverage percentages; test edge and misuse cases | `references/TESTING.md` |
| Constructors | `Config` in → concrete struct out; validate + default in `New`; use `Config.Validate()` when config logic grows | `references/CONFIG.md` |
| Errors | Use sentinels for durable branching; wrap with `%w` or `errors.Join`; keep `recover` at app boundaries | `references/ERRORS.md` |
| Logging | Packages do not log by default; hot-path logging is a performance decision | `references/LOGGING.md` |
| Interfaces | "Accept interfaces, return structs"; consumers usually define interfaces | `references/INTERFACES.md` |
| Documentation | Write idiomatic godoc and durable comments; never add agent-context comments | `references/DOCUMENTATION.md` |
| Layout | Keep packages shallow, avoid junk drawers, and follow repo conventions | `references/LAYOUT.md` |
| Entry Points | `main.go` is wiring only | `references/LAYOUT.md` |
| Benchmarks | Benchmark hot paths; use `b.ReportAllocs()` and compare runs with `benchstat` | `references/BENCHMARKS.md` |
| Testing | Table-driven, stdlib-first, defensive against misuse, and fuzz-heavy where inputs are complex | `references/TESTING.md` |
| Concurrency | Every goroutine needs a shutdown path; use `context.Context`, `-race`, and jitter where needed | `references/CONCURRENCY.md` |
| Reviews | Use the checklist when reviewing Go changes | `references/REVIEW-CHECKLIST.md` |

---

## Common Pitfalls

- Returning interfaces by default instead of concrete types.
- Treating coverage percentages as proof of correctness.
- Logging in reusable packages instead of returning errors.
- Passing global app config through packages rather than local `Config`.
- Leaving critical runtime knobs on dangerous defaults.
- Forcing a house directory layout onto repos that already have clear conventions.
- Loading every reference document before you know which topic the task touches.
- Shipping changes that claim performance wins without benchmarks or concurrency safety without `-race`.

---

## Core Principles

### Testability is first-class

- Prefer designs that are easy to test without booting an entire application.
- Inject dependencies explicitly.
- Keep pure logic isolated.
- Test edge cases, invalid inputs, and misuse paths rather than only happy paths.

### Config-driven construction

- Prefer `Config` in → struct out constructors.
- Validate at construction.
- Default explicitly.
- Make important runtime knobs visible and documented.

### Errors are a contract

- Prefer **sentinel errors** for durable conditions callers need to branch on.
- Use `%w` (or `errors.Join`) so callers can use `errors.Is/As`.
- Prefer a small set of durable meanings plus contextual wrapping.

### Benchmark what matters

- Add benchmarks for performance-sensitive code paths.
- Avoid "it's faster" claims without `go test -bench`.

### Packages are reusable by default

- Keep packages domain-focused and individually testable.
- Avoid global state and hidden side effects.

### Structure should reinforce intent

- Use package boundaries and entry points as architectural guardrails.
- Follow established repo conventions when they are clear.

---

## Package Types

### App package (orchestrator)

Owns:

- dependency wiring (DB, clients, loggers)
- lifecycle (start/stop)
- error policy (retry, ignore, crash)
- logging and metrics policy

### Non-app packages (reusable units)

Rules:

- No direct logging (see `references/LOGGING.md`)
- Return errors, don't hide them
- Define a local `Config`/`Opts` contract
- Accept initialized dependencies (DB/client/etc); do not create them internally

---

## Directory Structure

### Services / apps

- `cmd/<appname>/main.go` for entrypoints
- Keep `main.go` **thin**: parse config, wire dependencies, call the app entrypoint.

This guide often prefers service repos that group packages under `pkg/`, with
orchestration in something like `pkg/app`, but that is a house preference, not
Go law.

Example:

```text
cmd/myapp/main.go
pkg/...
pkg/app/...
```

If a repository already uses top-level packages, `internal/`, or a mixed shape
with clear rules, follow the repository convention instead of forcing `pkg/`.
Do not restructure an existing repository to introduce `pkg/` unless you were
explicitly asked to do that migration.

### Libraries

- Packages at top-level directories, not nested under `pkg/` or `internal/`.

- Avoid junk drawers (`utils`, `common`) unless they truly represent a domain.

---

## Constructors and Config

- `New(cfg Config) (*T, error)` or `Dial(cfg Config) (*T, error)`
- Prefer passing `Config` by value; validate + default inside constructor
- For complex configs, move non-trivial validation into `func (c *Config) Validate() error`
- Return a **concrete** type by default
- Treat constructor-normalized config as immutable internal state
- Config is owned by the package, not the app
- Avoid `init()` for normal construction; it usually hides globals, ordering
  dependencies, or side effects better handled by explicit setup
- Follow "accept interfaces, return structs": inject boundary interfaces and
  return concrete types unless there is a clear multi-implementation boundary
- Make important runtime knobs explicit: timeouts, pool sizes, lifetimes,
  backoff/retry ceilings, and similar operational settings
- Use explicit runtime controls for degraded modes in critical services; do not
  expect callers to mutate `Config` after construction

See: `references/CONFIG.md`, `references/INTERFACES.md`

---

## Logging

Logging is owned by the application.

If a package must log (rare async/network/runtime cases), inject
**`*slog.Logger`** via `Config`, default to discard, keep structured logs, and
prefer context-aware log methods when a real `context.Context` is already
available.

Treat hot-path logging as a performance decision. Avoid chatty request-path
`Info` logs, and if async logging is used, document buffering, backpressure,
and drop behavior.

See: `references/LOGGING.md`

---

## Errors

- Export `var ErrX = errors.New("...")` for stable, durable meanings callers may
  need to branch on
- Wrap with `%w` or use `errors.Join` so `errors.Is` works
- Don't use `%s` to wrap errors (it breaks unwrap semantics)
- Prefer a small set of sentinels plus contextual wrapping rather than a new
  sentinel for every failure path
- Keep `recover` at application boundaries or middleware, not in reusable
  packages
- Packages return errors; apps log them and decide whether to ignore, retry, or crash

See: `references/ERRORS.md`

---

## Testing

- Prefer table-driven tests with clear, behavior-oriented case names.
- Coverage is a signal, not proof; confidence comes from meaningful assertions
  and edge cases.
- Test defensive behavior, not just the current happy path.
- Use `go test -fuzz` for parsers, decoders, and other input-heavy code.
- Use `TestMain` only for true package-wide lifecycle setup/teardown.
- Run `-race` in CI for concurrency-sensitive code.

See: `references/TESTING.md`

---

## Documentation + Comments

- Public packages need package docs explaining purpose and main usage, using
  `/** ... */` package comments.
- Exported identifiers get idiomatic doc comments, helpful links like `[Config]`,
  and executable `Example_` docs when teaching usage matters. Functions,
  methods, types, vars, consts, and fields use `//` doc comments.
- Comments explain why, contract, or intent; never narrate obvious code.
- No agent-context comments or self-referential TODO/FIXME notes.

See: `references/DOCUMENTATION.md`

---

## Concurrency

- Every goroutine must have a clear shutdown path via `context.Context`.
- Long-lived services implement `Close()` or `Stop()` with concurrency synchronization to ensure graceful shutdown.
- Use `sync.Mutex` for complex state, `sync/atomic` for simple counters and flags.
- Prefer `select` with `ctx.Done()` for blocking operations.
- Use context-aware I/O APIs such as `QueryContext` and `NewRequestWithContext`.
- Use `defer` for cleanup in the scope that acquires a resource.
- Add jitter to recurring background work when synchronized schedules would
  create spikes.
- Graceful shutdown should fail readiness, drain in-flight work, stop listeners,
  and wait for tracked work to finish.
- If it's not tested with `-race`, assume it's not concurrency-safe.

See: `references/CONCURRENCY.md`

---

## File Organization and Efficiency

Files follow idiomatic ordering: package docs, imports, consts/vars, sentinel
errors, types, constructors, exported methods, unexported helpers. Avoid
catch-all files like `types.go` or `util.go`.

Keep hot-path structs compact (field ordering for padding) but do not
micro-optimize without benchmarks.

Use structure as an architectural guardrail. Package boundaries and entry
points should make the intended placement of new behavior obvious.

Avoid `init()` in general. It is often a sign of hidden globals, implicit
registration, or startup side effects that should be made explicit.

See: `references/LAYOUT.md`

---

## Benchmarks

Add benchmarks for hot-path functions, serialization, concurrency primitives,
and adapters in tight loops. Use `b.ReportAllocs()`, include realistic inputs,
and compare alternatives when proposing changes.

Let the runner control `b.N`, run important numbers on a quiet machine, and use
`benchstat` when comparing benchmark results.

See: `references/BENCHMARKS.md`

---

## Interfaces + Implementations

Default to small consumer-defined interfaces and producer-owned concrete
structs.

Use shared contract packages with subpackages (`drivers/`, `backends/`, etc.)
as a special case when the package's primary purpose is to define a common
boundary across multiple implementations.

See: `references/INTERFACES.md`

---

## Reference Index

Use these supporting documents when deeper detail is needed:

- [references/LOGGING.md](references/LOGGING.md)
  Logging rules: default no-logging-in-packages guidance, exceptions, `slog`
  injection, and hot-path cost guidance.

- [references/ERRORS.md](references/ERRORS.md)
  Durable error contracts, wrapping rules, and `errors.Is/As` guidance.

- [references/CONFIG.md](references/CONFIG.md)
  Canonical `Config` struct patterns, constructor validation + defaults, and
  operational controls.

- [references/INTERFACES.md](references/INTERFACES.md)
  Interface boundaries, consumer-defined defaults, and special-case driver
  patterns.

- [references/DOCUMENTATION.md](references/DOCUMENTATION.md)
  Package docs, idiomatic godoc, internal function comments, field docs, and durable comment rules.

- [references/LAYOUT.md](references/LAYOUT.md)
  File organization, struct field efficiency, package naming guidance, and
  architectural guardrails.

- [references/BENCHMARKS.md](references/BENCHMARKS.md)
  Benchmark expectations, templates, and result-comparison rules.

- [references/TESTING.md](references/TESTING.md)
  Stdlib-first testing patterns, table-driven tests, helpers, defensive testing,
  and test file conventions.

- [references/CONCURRENCY.md](references/CONCURRENCY.md)
  Goroutine lifecycle, context propagation, graceful shutdown, `-race`, jitter,
  and synchronization patterns.

- [references/REVIEW-CHECKLIST.md](references/REVIEW-CHECKLIST.md)
  PR review rubric for humans and coding agents.
