# Go Style Guide Skill

An opinionated agent skill for designing, reviewing, and refactoring Go code.

This repository packages a reusable skill plus supporting reference material for
Go engineering decisions around package design, constructors and config,
interfaces, errors, logging, documentation, layout, and benchmarks.

## What this is

The `go-style-guide` skill is a practical Go engineering guide for:

- new package and API design
- refactors and restructures
- code review
- testability and dependency injection decisions
- error and logging contracts
- performance-sensitive code that should be benchmarked

It is designed to be useful to both human engineers and coding agents.

## Opinionated by design

This guide reflects Benjamin Cane's personal engineering preferences. It is not
intended to be a universal or official Go style guide.

The goal is consistency, maintainability, and production readiness in real
codebases. If your repository already has established conventions, those should
still win.

## What it emphasizes

- testability-first package design
- `Config`-driven constructors with explicit validation and defaults
- boundary-driven interfaces, following "accept interfaces, return structs"
- sentinel-first error contracts with preserved wrapping semantics
- application-owned logging instead of hidden package logging
- idiomatic godoc and durable comments for public and important internal code
- benchmarks for performance-sensitive code paths
- shallow, domain-oriented package layouts

## Repository layout

```text
skills/
  go-style-guide/
    SKILL.md
    references/
      BENCHMARKS.md
      CONFIG.md
      CONCURRENCY.md
      DOCUMENTATION.md
      ERRORS.md
      INTERFACES.md
      LAYOUT.md
      LOGGING.md
      REVIEW-CHECKLIST.md
      TESTING.md
```

- `skills/go-style-guide/SKILL.md` is the main skill prompt.
- `skills/go-style-guide/references/` contains deeper reference material that
  the skill can rely on when needed.

## Installing the skill

Copy the `skills/go-style-guide/` directory into either:

- your repository's `.agents/skills/` directory (or `.devin/skills/` for Devin)
- your user-level `~/.agents/skills/` directory (or `~/.config/devin/skills/` for Devin)

This path convention is supported by Devin and other agent tools that read
skill directories. Adapt the destination to your tool's convention if it
differs.

In both cases, the final path should end with:

```text
.agents/skills/go-style-guide/SKILL.md
```

The directory name becomes the skill identifier, so the skill should remain
named `go-style-guide` unless you intentionally want a different invocation
name.

Example:

```text
your-project/
  .agents/
    skills/
      go-style-guide/
        SKILL.md
        references/
```

Or install it globally:

```text
~/.agents/
  skills/
    go-style-guide/
      SKILL.md
      references/
```

Once installed, invoke it using the mechanism your agent tool provides for
running skills. The skill identifier is `go-style-guide`.

The skill files in this repository are already organized so they can be copied
directly into `.agents/skills/go-style-guide/`.

## Compatibility notes

The examples in this repository assume modern Go and use standard-library
features such as `errors.Join` and `log/slog`. Go 1.21+ is a good baseline.

If you apply this guide to an older repository, adapt the recommendations to the
Go version that repository actually supports.

## Reference documents

The supporting documents are organized by topic and are intended for on-demand
lookup. Agents should start with `SKILL.md` and read only the specific
`references/*.md` files needed for the current task:

- [Configuration + Constructors](skills/go-style-guide/references/CONFIG.md)
- [Interfaces + Implementations](skills/go-style-guide/references/INTERFACES.md)
- [Error Handling](skills/go-style-guide/references/ERRORS.md)
- [Logging](skills/go-style-guide/references/LOGGING.md)
- [Documentation + Comments](skills/go-style-guide/references/DOCUMENTATION.md)
- [Layout](skills/go-style-guide/references/LAYOUT.md)
- [Benchmarks](skills/go-style-guide/references/BENCHMARKS.md)
- [Testing](skills/go-style-guide/references/TESTING.md)
- [Concurrency](skills/go-style-guide/references/CONCURRENCY.md)
- [Review Checklist](skills/go-style-guide/references/REVIEW-CHECKLIST.md)

## Contributing

Contributions are welcome. Please read
[CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## License

This project is licensed under [Apache-2.0](LICENSE).
