# Testing (Stdlib-First)

Tests are a first-class engineering artifact, not an afterthought.

## Table of Contents

- [Core Principles](#core-principles)
- [Why Stdlib Over Assertion Libraries](#why-stdlib-over-assertion-libraries)
- [Stdlib Assertion Patterns](#stdlib-assertion-patterns)
- [Table-Driven Test Template](#table-driven-test-template)
- [Test Helpers](#test-helpers)
- [Defensive Tests Protect Future Callers](#defensive-tests-protect-future-callers)
- [Fuzz Testing for Input-Heavy Code](#fuzz-testing-for-input-heavy-code)
- [Testing with Config-First Packages](#testing-with-config-first-packages)
- [testdata Convention](#testdata-convention)
- [Integration vs Unit Tests](#integration-vs-unit-tests)
- [Test File Conventions](#test-file-conventions)
- [What Not To Do](#what-not-to-do)
- [Summary](#summary)

---

This style guide treats the **standard library** as the default testing toolkit.
External assertion libraries are not required and should not be the default
dependency for new projects.

---

## Core Principles

### 1. Use the Standard Library by Default

Go's `testing` package provides everything needed for clear, maintainable tests:

- `t.Fatal` / `t.Fatalf` — stop the test immediately
- `t.Error` / `t.Errorf` — record a failure, keep running
- `t.Log` / `t.Logf` — diagnostic output (shown on failure or `-v`)
- `t.Run` — subtests
- `t.Parallel` — parallel execution
- `t.Helper` — clean up call-site reporting
- `t.Cleanup` — deferred teardown
- `t.TempDir` — managed temporary directories

No additional dependencies are needed for the vast majority of Go tests.

### 2. Table-Driven Tests Are the Preferred Shape

Table-driven tests reduce duplication, make coverage visible, and are easy
to extend.

### 3. Subtests for Variants and Parallel Execution

Use `t.Run` to isolate cases. Use `t.Parallel()` when tests do not share
mutable state.

### 4. Packages Must Be Independently Testable

Tests should not require booting the full application. Config-first design
and interface injection make this possible by default.

### 5. Coverage Is Directional, Not Confidence

Coverage is a useful signal, not proof of correctness.

High coverage can still miss:

- weak assertions
- happy-path-only tests
- invalid input handling
- future misuse of the API

Good tests increase confidence by checking behavior, contracts, and failure
handling, not by chasing a percentage alone.

### 6. Fuzz Parsers and Input-Heavy Code

When a function accepts arbitrary user input, parses wire formats, decodes
files, tokenizes text, or otherwise has a large input space, add a fuzz test.

`go test -fuzz` is part of the standard library workflow. Use it for code that
is easy to crash, hang, or push into invalid states with unexpected input.

---

## Why Stdlib Over Assertion Libraries

Stdlib assertions are:

- **Explicit** — the failure message says exactly what went wrong
- **Zero-dependency** — no extra modules to manage or version
- **Grep-friendly** — failure output maps directly to code
- **Flexible** — no framework opinions about output format

Libraries like testify are acceptable in existing codebases that already use
them. But new projects should not add them by default.

Common concern: "stdlib tests are verbose."

In practice, a well-written stdlib test is only a few lines longer, and those
lines carry useful context that assertion libraries often obscure.

---

## Stdlib Assertion Patterns

### Fatal vs Error

Use `t.Fatal` / `t.Fatalf` when the test **cannot continue**:

```go
e, err := New(cfg)
if err != nil {
    t.Fatalf("New() unexpected error: %v", err)
}
```

Use `t.Error` / `t.Errorf` when you want to **record the failure and keep
checking**:

```go
if got != want {
    t.Errorf("Get() = %q, want %q", got, want)
}
```

Rule of thumb: use `Fatal` for setup; use `Error` for assertions on results.

---

### Checking Errors

Check for unexpected errors:

```go
if err != nil {
    t.Fatalf("Run() unexpected error: %v", err)
}
```

Check that an error is returned:

```go
if err == nil {
    t.Fatal("Run() expected error, got nil")
}
```

Check for a specific sentinel:

```go
if !errors.Is(err, ErrNotFound) {
    t.Fatalf("Run() error = %v, want %v", err, ErrNotFound)
}
```

Check for a typed error:

```go
var se *StatusError
if !errors.As(err, &se) {
    t.Fatalf("Run() error type = %T, want *StatusError", err)
}
if se.Code != 404 {
    t.Errorf("StatusError.Code = %d, want 404", se.Code)
}
```

---

### Comparing Values

Simple equality:

```go
if got != want {
    t.Errorf("Count() = %d, want %d", got, want)
}
```

Struct or slice comparison with `reflect.DeepEqual`:

```go
if !reflect.DeepEqual(got, want) {
    t.Errorf("List() = %v, want %v", got, want)
}
```

For complex structs where diff output helps debugging, `go-cmp` is a
reasonable optional dependency:

```go
if diff := cmp.Diff(want, got); diff != "" {
    t.Errorf("Result mismatch (-want +got):\n%s", diff)
}
```

`go-cmp` is not stdlib, but it is widely accepted in the Go ecosystem for
test-only use. It is the one external test dependency this guide considers
reasonable when diff output adds genuine value.

---

## Table-Driven Test Template

```go
func TestWorker_Run(t *testing.T) {
    tests := []struct {
        name    string
        input   []byte
        wantErr error
    }{
        {
            name:    "valid input",
            input:   []byte("hello"),
            wantErr: nil,
        },
        {
            name:    "nil input returns error",
            input:   nil,
            wantErr: ErrInvalidInput,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            t.Parallel()

            w, err := New(Config{Runner: fakeRunner{}})
            if err != nil {
                t.Fatalf("New() unexpected error: %v", err)
            }

            _, err = w.Run(context.Background(), tt.input)

            if tt.wantErr != nil {
                if !errors.Is(err, tt.wantErr) {
                    t.Fatalf("Run() error = %v, want %v", err, tt.wantErr)
                }
                return
            }
            if err != nil {
                t.Fatalf("Run() unexpected error: %v", err)
            }
        })
    }
}
```

### Naming Conventions

- `TestType_Method` — `TestWorker_Run`, `TestCache_Get`
- `TestFunction` — `TestParseDuration`, `TestValidateConfig`
- Subtest names should be short, descriptive, and lowercase-friendly
- Prefer behavior-oriented case names like `error when timeout exceeded` or
  `returns cached value on hit`, not placeholders like `case 1` or `happy path`
  when a more specific behavior can be named

---

## Test Helpers

### `t.Helper()`

Mark helper functions so failures report the caller's line, not the helper's:

```go
func assertNoError(t *testing.T, err error) {
    t.Helper()
    if err != nil {
        t.Fatalf("unexpected error: %v", err)
    }
}
```

Building small, project-specific helpers with `t.Helper()` is the idiomatic
alternative to importing an assertion library.

### `t.Cleanup()`

Register teardown that runs after the test (and subtests) complete:

```go
func TestWithTempDB(t *testing.T) {
    db := setupTestDB(t)
    t.Cleanup(func() { db.Close() })

    // test logic
}
```

Prefer `t.Cleanup` over `defer` when the resource is created in a helper
function, since `defer` scopes to the helper, not the test.

### `t.TempDir()`

Returns a temporary directory that is automatically removed after the test:

```go
func TestFileStore_Write(t *testing.T) {
    dir := t.TempDir()

    s, err := NewFileStore(Config{Dir: dir})
    if err != nil {
        t.Fatalf("NewFileStore() error: %v", err)
    }

    // test logic using s
}
```

---

## Defensive Tests Protect Future Callers

Do not only test the way the code is used today. Test how it could be misused
tomorrow.

When a function accepts input, add cases for:

- nil values
- empty input
- too few or too many items
- malformed or junk data
- repeated or out-of-order calls when relevant

This is defensive programming in test form. Code changes over time, and future
callers may not preserve the assumptions the original implementation relied on.

If an API should reject misuse, test that it rejects misuse clearly. If it
should tolerate misuse, test that it degrades safely.

---

## Fuzz Testing for Input-Heavy Code

Fuzz tests are a required tool for parsers, decoders, protocol handlers, and
other input-heavy functions where table-driven tests alone cannot cover the
interesting state space.

Use fuzzing when code:

- accepts untrusted or semi-structured input
- parses text, bytes, or config files
- tokenizes or normalizes user-controlled data
- has historically had panic or bounds-check bugs
- should never hang or allocate unboundedly for malformed input

Keep the fuzz target narrow and deterministic. The goal is to assert durable
invariants such as "never panic," "either returns a valid result or a stable
error," and "malformed input does not wedge the process."

Example:

```go
func FuzzParseDurationList(f *testing.F) {
    f.Add("1s,2m,3h")
    f.Add("")
    f.Add("not-a-duration")

    f.Fuzz(func(t *testing.T, input string) {
        got, err := ParseDurationList(input)
        if err != nil {
            return
        }
        if len(got) == 0 && input != "" {
            t.Fatalf("ParseDurationList(%q) returned empty result without error", input)
        }
    })
}
```

Run focused fuzzing while developing:

```sh
go test -fuzz=FuzzParseDurationList ./...
```

When a fuzz run finds a bug, keep the minimized crashing input and add an
ordinary unit test for the regression. Fuzzing expands coverage; it does not
replace readable regression tests.

---

## Testing with Config-First Packages

The Config pattern makes testing straightforward:

### Inject fakes via Config

```go
type fakeRunner struct {
    out []byte
    err error
}

func (f fakeRunner) Run(ctx context.Context, input []byte) ([]byte, error) {
    return f.out, f.err
}

func TestWorker_Success(t *testing.T) {
    w, err := New(Config{
        Runner: fakeRunner{out: []byte("ok")},
    })
    if err != nil {
        t.Fatalf("New() unexpected error: %v", err)
    }

    got, err := w.Run(context.Background(), []byte("input"))
    if err != nil {
        t.Fatalf("Run() unexpected error: %v", err)
    }
    if string(got) != "ok" {
        t.Errorf("Run() = %q, want %q", got, "ok")
    }
}
```

### Test constructor validation

```go
func TestNew_MissingRunner(t *testing.T) {
    _, err := New(Config{})
    if !errors.Is(err, ErrInvalidConfig) {
        t.Fatalf("New() error = %v, want %v", err, ErrInvalidConfig)
    }
}
```

### Test defaults

```go
func TestNew_DefaultTimeout(t *testing.T) {
    w, err := New(Config{Runner: fakeRunner{}})
    if err != nil {
        t.Fatalf("New() unexpected error: %v", err)
    }
    if w.cfg.Timeout != DefaultTimeout {
        t.Errorf("timeout = %v, want %v", w.cfg.Timeout, DefaultTimeout)
    }
}
```

---

## testdata Convention

Go ignores directories named `testdata` during builds. Use it for:

- fixture files (JSON, YAML, binary blobs)
- golden files for snapshot testing
- sample configs for integration tests

Example:

```text
pkg/parser/
  parser.go
  parser_test.go
  testdata/
    valid.json
    malformed.json
```

Load fixtures with:

```go
data, err := os.ReadFile(filepath.Join("testdata", "valid.json"))
```

For golden files, it is common to support an `-update` flag that rewrites the
expected files when an output change is intentional. This keeps golden updates
explicit and reviewable instead of requiring hand-edits.

---

## Integration vs Unit Tests

### Unit tests

- Fast, parallel, no external dependencies
- Use fakes and injected boundaries
- Run on every commit

### Integration tests

Guard integration tests behind build tags or a `-short` skip:

```go
func TestDatabaseIntegration(t *testing.T) {
    if testing.Short() {
        t.Skip("skipping integration test in short mode")
    }

    // real database setup
}
```

Or use a build tag:

```go
//go:build integration

package store_test
```

### Race detection

Always run tests with `-race` in CI:

```sh
go test -race ./...
```

This catches data races that are invisible during normal execution.

---

## Test File Conventions

### Co-locate tests with source

```text
pkg/worker/
  worker.go
  worker_test.go
```

### `TestMain(m *testing.M)`

Use `TestMain` when a package needs true global setup or teardown, such as
starting a Docker-backed dependency, seeding shared integration fixtures, or
creating expensive shared state once for the package.

Keep `TestMain` narrow:

- prefer ordinary helpers and `t.Cleanup()` for most setup
- use `TestMain` only for package-wide lifecycle concerns
- avoid hiding test-specific behavior that individual tests should control

Example:

```go
func TestMain(m *testing.M) {
    // global setup
    code := m.Run()
    // global teardown
    os.Exit(code)
}
```

### Black-box vs white-box

Prefer black-box tests (`package worker_test`) to test the public API:

```go
package worker_test

import "myapp/pkg/worker"
```

Use white-box tests (`package worker`) only when testing unexported behavior
that is critical to correctness.

### export_test.go

If white-box access is needed from a black-box test file, use `export_test.go`
to expose unexported symbols for testing:

```go
// export_test.go
package worker

var ExportedInternalFunc = internalFunc
```

This keeps production code clean while enabling targeted test access.

---

## What Not To Do

### Do not add assertion libraries by default

Testify and similar libraries are fine in projects that already use them.
Do not add them to new projects as a default dependency.

Stdlib + small helpers built with `t.Helper()` cover the same ground with
fewer dependencies and clearer failure output.

### Do not test unexported functions directly

Test through the public API. If unexported logic is complex enough to need
its own tests, consider whether it should be extracted into its own package.

### Do not skip `t.Parallel()` without reason

Parallel tests catch shared-state bugs and run faster. Only omit
`t.Parallel()` when tests genuinely share mutable state that cannot be
isolated.

### Do not use `init()` in test files

Test setup belongs in `TestMain`, `t.Cleanup`, or individual test functions.
`init()` in test files creates hidden, hard-to-debug ordering dependencies.

---

## Summary

- The standard library is the default testing toolkit.
- Table-driven tests with `t.Run` and `t.Parallel()` are the preferred shape.
- Table-driven case names should describe behavior, not generic labels.
- Coverage is directional; confidence comes from meaningful assertions and edge cases.
- Test defensive behavior, not just the current happy path.
- Use `t.Fatal` for setup failures; `t.Error` for result assertions.
- Build small helpers with `t.Helper()` instead of importing assertion libraries.
- Config-first packages are naturally testable via fake injection.
- Use `testdata/` for fixtures and golden files; the `-update` pattern is idiomatic.
- Use `TestMain` only for package-wide setup/teardown that cannot live in normal tests.
- Guard integration tests with `-short` or build tags.
- Use `go test -fuzz` for parsers and other input-heavy code.
- Always run `-race` in CI.

---

## Guiding Rule

**Tests should be as clear and maintainable as the code they verify.**
