# Interfaces + Implementations (Boundary-Driven Design)

Interfaces are one of Go's most powerful tools.

In this style guide, interfaces are treated as:

- **testability primitives**
- **package boundaries**
- **driver/plugin contracts**
- **coordination surfaces**

Not as default return types everywhere.

---

## Core Philosophy

### Interfaces Improve Testability

Interfaces make code easier to test by allowing injection of:

- fakes
- mocks
- alternate implementations
- runtime drivers

Example:

```go
type Database interface {
    Get(ctx context.Context, key string) ([]byte, error)
    Set(ctx context.Context, key string, value []byte) error
    Close() error
}
```

Your application becomes testable without spinning up real dependencies.

---

## Rule: Interfaces Belong at Boundaries

Interfaces should exist where the system crosses a boundary:

- database driver
- runtime capability
- external service boundary
- logging sink
- queue or scheduler backend

Good:

```go
type Runner interface {
    Run(ctx context.Context, input []byte) ([]byte, error)
}
```

Good:

```go
type KVStore interface {
    Get(key string) ([]byte, error)
}
```

Bad:

```go
type UserService interface {
    DoThing()
}
```

If there is only one implementation and no boundary, the interface is usually unnecessary.

As a default, the **consumer** of a dependency should define the interface it
needs, while the **producer** should usually export a concrete struct. This
keeps interfaces small and demand-driven instead of forcing every consumer to
adopt a producer-owned abstraction they may not actually need.

---

## Rule: Prefer Small Interfaces

Interfaces should be:

- narrow
- capability-focused
- stable

For single-method interfaces, prefer descriptive `-er` names when they fit the
capability: `Runner`, `Storer`, `Getter`, `Reader`, `Closer`.

Good:

```go
type Reader interface {
    Read(p []byte) (int, error)
}
```

Good:

```go
type Logger interface {
    Error(msg string, args ...any)
}
```

Bad:

```go
type Everything interface {
    Start()
    Stop()
    Reload()
    Debug()
    Export()
    Metrics()
}
```

Large interfaces reduce flexibility and are harder to mock correctly.

---

## Special Pattern: Shared Contract Package + Driver Subpackages

This is the "drivers" model used in many Go libraries, but it is a special case,
not the default for ordinary packages.

Use it when the package's primary purpose is to define a shared contract across
multiple implementations, such as drivers, backends, or plugins.

Example structure:

```text
pkg/kvstore/
├── kvstore.go           # Interface + shared errors/constants
├── drivers/
│   ├── file/
│   ├── memory/
│   ├── noop/
│   └── mock/
```

### Root Interface

```go
package kvstore

type Database interface {
    Get(ctx context.Context, key string) ([]byte, error)
    Set(ctx context.Context, key string, value []byte) error
    Close() error
}
```

### Driver Implementation

```go
package memory

type Database struct {
    items map[string][]byte
}

func Dial(cfg Config) (*Database, error) {
    ...
}
```

This keeps:

- contract stable
- implementations modular
- testing straightforward

This pattern works well for packages such as `pkg/kvstore`, where the top-level
package owns the interface, sentinel errors, shared constants, and common
contract language, while `pkg/kvstore/drivers/...` contains concrete driver
implementations.

For ordinary packages, prefer the simpler default: the consumer defines the
small interface it needs, and the producer exports a concrete struct.

Compile-time interface satisfaction checks are useful when you want an explicit
guarantee that a driver still matches the boundary contract:

```go
var _ kvstore.Database = (*memory.Database)(nil)
```

Use these checks sparingly at implementation boundaries where they add signal.

---

## Rule: "Accept Interfaces, Return Structs"

This Go proverb fits the preferred package design here:

- accept interfaces at package boundaries
- return concrete structs from constructors by default

That keeps dependency injection flexible while preserving discoverability for
callers.

---

## Rule: Constructors Usually Return Concrete Types

Preferred:

```go
func Dial(cfg Config) (*Database, error)
```

Not:

```go
func Dial(cfg Config) (store.Database, error)
```

Concrete returns provide:

- clearer API surface
- discoverability
- easier extension

---

## When Returning Interfaces Is Correct

Returning an interface is appropriate when:

### Multiple Implementations Are Expected

```go
func Open(cfg Config) (Database, error)
```

### The Implementation Must Remain Hidden

```go
func New(cfg Config) (Executor, error)
```

### Plugin/Driver Selection Happens at Runtime

```go
switch cfg.Driver {
case "memory":
    return memory.Dial(...)
case "mock":
    return mock.Dial(...)
}
```

---

## Rule: Do Not Define Interfaces "For Mocking"

Interfaces should reflect **real boundaries**, not just unit-test convenience.

Bad:

```go
type Foo interface {
    DoFoo()
}
```

if Foo exists only so tests can mock it.

Instead:

- test against concrete structs
- inject real boundaries (DB, runners, queues)

---

## Injection Pattern: Config + Interface Boundary

Interfaces are often injected through Config.

Example:

```go
type Config struct {
    Database store.Database
    Logger   *slog.Logger
}
```

Constructor:

```go
func New(cfg Config) (*Service, error) {
    if cfg.Database == nil {
        return nil, ErrDatabaseRequired
    }
    return &Service{db: cfg.Database}, nil
}
```

---

## Function Interfaces (SDK-Like Pattern)

In SDK-style packages, a function type is often the best interface.

Example:

```go
type Config struct {
    Run func(ctx context.Context, input []byte) ([]byte, error)
}
```

This avoids large mock surfaces while still enabling test injection.

---

## Interfaces and Error Contracts

Interfaces should pair with:

- sentinel errors
- `errors.Is` compatibility
- predictable failure modes

Example:

```go
var ErrNotFound = errors.New("not found")

func (d *Database) Get(...) error {
    return fmt.Errorf("%w: %s", ErrNotFound, key)
}
```

---

## Summary Rules

- Interfaces exist for boundaries and testability
- Consumers usually define the interfaces they depend on
- Producers usually export concrete structs
- Keep interfaces small and capability-driven
- Prefer descriptive `-er` names for single-method interfaces
- Prefer top-level interface + subpackage implementations
- Use compile-time interface satisfaction checks where they clarify contracts
- Constructors return concrete structs by default
- Follow "accept interfaces, return structs"
- Return interfaces only when required by design
- Inject dependencies via Config
- Pair interfaces with sentinel errors and errors.Is contracts

---

## Guiding Rule

**Interfaces should clarify architecture, not obscure it.**
