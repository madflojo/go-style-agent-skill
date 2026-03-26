.DEFAULT_GOAL := help

MARKDOWNLINT ?= markdownlint-cli2
LYCHEE ?= lychee

.PHONY: help lint lint-markdown lint-links clean

help:
	@printf '%s\n' \
		'Available targets:' \
		'  make lint           Run all local Markdown checks' \
		'  make lint-markdown  Lint Markdown files with markdownlint-cli2' \
		'  make lint-links     Check Markdown links with lychee (offline)' \
		'  make clean          No-op for this docs-only repository'

lint: lint-markdown lint-links

lint-markdown:
	@command -v $(MARKDOWNLINT) >/dev/null 2>&1 || { \
		echo 'markdownlint-cli2 is required for make lint-markdown'; \
		exit 1; \
	}
	@find . -name '*.md' -print0 | xargs -0 $(MARKDOWNLINT)

lint-links:
	@command -v $(LYCHEE) >/dev/null 2>&1 || { \
		echo 'lychee is required for make lint-links'; \
		exit 1; \
	}
	@find . -name '*.md' -print0 | xargs -0 $(LYCHEE) --offline --no-progress --include-fragments

clean:
	@echo 'Nothing to clean.'
