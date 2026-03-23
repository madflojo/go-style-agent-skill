# Benchmarks (Performance as a First-Class Concern)

This style guide treats benchmarks as a normal part of Go engineering—not an afterthought.

Benchmarks help:

- validate performance assumptions
- prevent regressions
- guide optimizations with data
- compare alternate designs (mutex vs atomic, JSON vs protobuf, etc.)

Benchmarks are especially important for:

- packages used in hot paths
- concurrency primitives and coordination code
- serialization/deserialization
- transport/client behavior
- caching and lookup logic
- parsing and validation logic
- allocations and memory churn

---

## Rules

### 1) Benchmark performance-sensitive code by default

If a package is likely to be used frequently or in tight loops, include at least:

- a baseline benchmark
- a benchmark for the common path
- a benchmark for an error/edge path (if meaningful)

### 2) Benchmarks should be stable and repeatable

Avoid:

- real network calls
- real time sleeps
- random behavior without seeding
- OS/environment dependency where possible

Prefer:

- in-memory fakes
- deterministic test data
- controlled concurrency

When collecting numbers you care about, run benchmarks on a reasonably quiet
machine. Background tools such as Slack, Zoom, screen recording, large Chrome
sessions, and other heavy workloads can add enough noise to make small changes
look real when they are not.

### 3) Capture allocations and report them

Use:

```go
b.ReportAllocs()
```

Allocations matter as much as raw speed in Go, especially for libraries.

### 4) Benchmark before optimizing

Optimization without measurement is guessing.

If you are changing:

- data structures
- concurrency model
- API shape
- buffering
- encoding formats
- caching approaches

…add or update a benchmark first.

### 5) Benchmark at the right level

Include benchmarks that match how users will call the code:

- low-level microbenchmarks (tight loops, pure funcs)
- boundary benchmarks (interface calls, transport calls, marshal/unmarshal)
- concurrency benchmarks (contention patterns)

---

## Benchmark File Conventions

- Use `*_benchmark_test.go` files with `BenchmarkXxx` funcs.
- Name clearly: `BenchmarkMarshalSmall`, `BenchmarkMarshalLarge`,
  `BenchmarkGetHit`, `BenchmarkGetMiss`, etc.

Example layout:

```text
pkg/foo/
  foo.go # implementation
  foo_test.go # tests
  foo_benchmark_test.go # benchmarks
```

---

## Standard Benchmark Template

```go
func BenchmarkThing(b *testing.B) {
    b.ReportAllocs()

    // Arrange (outside loop)
    input := makeInput()

    b.ResetTimer()
    for i := 0; i < b.N; i++ {
        _, _ = DoThing(input)
    }
}
```

`b.N` is controlled by the benchmark runner. It increases dynamically until the
runner has enough samples to report a stable result, so benchmark code should
loop over `b.N` and never try to set it manually.

### Timer Discipline

- Do setup **before** `b.ResetTimer()`
- If you must do per-iteration setup, use `b.StopTimer()` / `b.StartTimer()` carefully.

---

## Table-Driven Benchmarks

When the same operation has meaningful variants (sizes, configs, modes):

```go
func BenchmarkParse(b *testing.B) {
    cases := []struct{
        name string
        in   []byte
    }{
        {"small", smallPayload},
        {"medium", mediumPayload},
        {"large", largePayload},
    }

    for _, tc := range cases {
        b.Run(tc.name, func(b *testing.B) {
            b.ReportAllocs()
            b.ResetTimer()
            for i := 0; i < b.N; i++ {
                _, _ = Parse(tc.in)
            }
        })
    }
}
```

---

## Concurrency Benchmarks

Use `b.RunParallel` for contention / parallel workload simulation:

```go
func BenchmarkCacheGetParallel(b *testing.B) {
    b.ReportAllocs()

    c := NewCache(...)
    key := "k"

    b.ResetTimer()
    b.RunParallel(func(pb *testing.PB) {
        for pb.Next() {
            _, _ = c.Get(key)
        }
    })
}
```

If benchmarking lock contention:

- benchmark read-heavy vs write-heavy separately
- benchmark with different goroutine counts if needed

---

## Avoid Benchmark Traps

### Trap: compiler optimizations removing work

If the compiler can eliminate unused results, your benchmark lies.

Use:

- return values
- package-level sinks

Example:

```go
var sink any

func BenchmarkWork(b *testing.B) {
    for i := 0; i < b.N; i++ {
        sink = Work()
    }
}
```

### Trap: comparing apples to oranges

If comparing two approaches:

- keep input identical
- ensure behavior is equivalent
- isolate only the intended difference

---

## Benchmarking IO / Network Code

Prefer benchmarking:

- request/response encoding
- constructor behavior
- parsing
- retry logic decisions

Avoid real external calls in benchmarks.

If you need realism:

- use local in-memory fakes
- or a loopback server started once outside the timer

---

## Regression Discipline

When performance matters:

- require benchmarks for PRs that change hot paths
- capture baseline numbers before and after changes
- document the expectation (ex: "must not regress allocs")

Good commit/PR notes:

- "Benchmark X improved 18%, allocs unchanged"
- "Benchmark Y regressed 2% due to added safety; accepted because correctness gained"

---

## Comparing results with benchstat

Use `benchstat` to compare benchmark output files and check whether a change is
statistically meaningful. It is the standard Go tool for comparing benchmark
runs.

Example workflow:

```sh
go test -bench=. -benchmem ./... > old.txt
go test -bench=. -benchmem ./... > new.txt
benchstat old.txt new.txt
```

This is especially useful when the raw benchmark output looks close enough that
eyeballing the numbers is misleading.

---

## Summary

Benchmarks are part of the engineering contract.

- Measure before optimizing
- Report allocations
- Let the runner control `b.N`; benchmark code should just loop over it
- Prefer repeatable tests
- Run important benchmarks on a quiet machine to reduce background noise
- Use `benchstat` to compare benchmark result files
- Include concurrency coverage when relevant
- Use benchmarks as regression guards

If a change might impact performance, a benchmark should exist to prove it.
