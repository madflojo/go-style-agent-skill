# Contributing

Thanks for your interest in improving this repository.

This project is an opinionated Go style skill. Contributions are welcome, but
changes should preserve a clear point of view rather than trying to accommodate
all possible Go preferences.

## What contributions are useful

Good contributions include:

- clarifying ambiguous guidance
- fixing grammar, formatting, or broken links
- improving code examples
- making examples more generic and less product-specific
- tightening consistency across the main skill and reference docs
- proposing additions that strengthen the guide's practical usefulness

## Before you open a PR

For larger changes, open an issue or start a discussion first if the proposal
would:

- change a core recommendation
- add a new major topic
- weaken an intentionally opinionated rule
- introduce tool-specific behavior that affects portability

Small fixes and editorial improvements can go straight to a pull request.

## Contribution guidelines

Please keep these principles in mind:

1. Keep examples generic.
   - Avoid product names, internal project references, or company-specific
     assumptions unless there is a strong reason to include them.

2. Preserve the opinionated voice.
   - This repository documents a preferred way of structuring Go code.
   - Contributions should improve the guide, not turn it into an exhaustive
     catalog of every acceptable alternative.

3. Keep documents consistent.
   - If you change a recommendation in one file, update related references so
     the guidance stays aligned.

4. Prefer concrete, testable advice.
   - Recommendations should be actionable for real code reviews and
     implementation work.

5. Proofread carefully.
   - Check grammar, formatting, heading structure, and Markdown links before
     submitting.

6. Add validation artifacts when guidance changes meaningfully.
   - If you change how the skill should behave, consider updating sample
     prompts, expected outputs, or other reviewable examples so future changes
     have something concrete to compare against.

## Pull request expectations

A good pull request is:

- focused in scope
- clear about the reason for the change
- consistent with the rest of the repository
- updated anywhere else the same guidance appears

If your change modifies wording that appears in multiple files, please update
all relevant files in the same pull request.

## Commit messages and releases

This repository uses Release Please to generate release pull requests, tags, and
GitHub Releases from conventional commit history.

Please prefer conventional commit prefixes for merged changes:

- `feat:` for new guidance, major additions, or materially expanded examples
- `fix:` for corrections to guidance, examples, links, or behavior
- `docs:` for user-visible documentation improvements worth noting in releases
- `refactor:` for structural cleanup that changes organization but not guidance
- `perf:` for performance-focused benchmark or efficiency improvements
- `chore:`, `ci:`, `build:`, and `test:` for internal maintenance changes

Examples:

- `feat: add concurrency shutdown guidance`
- `fix: correct error wrapping example`
- `docs: clarify global skill installation path`

Release Please uses Git tags as the canonical repository version. The
`metadata.version` field in `skills/go-style-guide/SKILL.md` is informational
only and is not release-managed.

Changes merged without a conventional commit prefix can still land, but they may
not produce useful release notes.

## Repository structure

The skill lives in:

```text
skills/go-style-guide/
```

The main prompt is `SKILL.md`, and the `references/` directory contains the
supporting documents used to expand on specific topics.
