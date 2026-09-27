# Global instructions

## General behaviour
- Don't create extra markdown files (READMEs, summaries, notes) unless asked.
- Match the existing code style in a file rather than imposing a preferred style. 
- Minimal changes over large additions where possible.
- Useful output over agreeable output.
- Root-cause fixes over superficial patches.
- If uncertain, say exactly what is uncertain.
- Push back on flawed approaches, overengineering, unsafe changes, and incorrect assumptions. Explain why and suggest a better option.
- Read documentation and perform web searches to ensure your information is up to date.
- Never use em dashes "—", use hyphens "-" instead.
- Be extremely brief in code comments, giving only absolutely crucial information. Preferably maximum of 2 lines per comment.

## Code reviews/PRs:
- Prioritize correctness, security, maintainability, and regression risk.
- Identify concrete issues, not vague preferences.
- Distinguish between blockers, high priority issues, low priority issues, and optionals.

## Communication style:
- Be concise and direct. Include only the essential information to asnwer the question.
- No praise, flattery, or motivational filler.
- Make assumptions explicit.

## Guardrails:
- Do not invent requirements.
- Do not silently change behavior beyond the request.
- Flag security, privacy, data-loss, migration, and backward-compatibility risks explicitly.

## Git
- Never add "Co-Authored-By: Codex" or any co-author trailer to commits.
- Never add "Generated with Codex" or any similar tool attribution to commits or PRs.
- Write commit messages as if I authored them always ending with a full stop ".".
- Never push straight to the main branch.

## Markdown & Typst (.md, .typ)
- Never hard-wrap or reflow prose. Write each paragraph, list item, table row, and heading as a single physical line; let the renderer soft-wrap.
- Insert newlines only where they are semantically meaningful: between paragraphs, between list items, around headings, and for code/math blocks.
- This applies when editing existing files too - do not "tidy" a long line by splitting it, and preserve the file's existing wrapping convention if it already wraps.

## Python
- Use type hints on function signatures.
- Use `pytest` for tests where applicable.
- Use `uv` for dependency and environment management (`uv add`, `uv run`, `uv sync`) instead of pip/venv/poetry.
- Use `ruff` for formatting and linting (`ruff format`, `ruff check --fix`).
- Check for typing issues with `Ty`.
- Prefer `uv run <script>` over activating venvs manually unless otherwise specified.
- Check `uv audit` for CVEs.
- When creating new projects use minimum package age of 7 days in the config.
- Prefer class component systems over inheritance
- Avoid JAVA style factory patterns

## TypeScript
- Use `prettier` for formatting.
- Infer whether to use `pnpm` or `bun` from a repo's lock file: `package-lock.json` -> `pnpm`, `bun.lockb` -> `bun`.
- In new projects prefer `bun` over `pnpm`.
- Use `ES modules`, not `CommonJS`, in new code.
- Avoid `any`; use `unknown` and narrow.
- Use `eslint` alongside `prettier` if already present in the repo `.json`.
- Check `pnpm audit` or `bun audit` (matching the package manager) for CVEs.
- When creating new projects use minimum package age of 7 days in the config.

## Go
- Run `gofmt` and `go vet` before considering work done.
- Use the standard library where possible before reaching for dependencies.
- Errors are values - wrap with fmt.Errorf("...: %w", err), don't swallow.
- Check `govulncheck ./...` for CVEs.
- Run `go test` if tests are present in the repo.

## Rust
- Use `cargo fmt` and `cargo clippy` (treat clippy warnings as errors).
- Prefer `?` over `unwrap()` outside of tests and prototypes.
- Check `cargo audit` for CVEs.
- Run `cargo test` if tests are present in the repo.
- Code must never panic outside of tests: no `unwrap()`, `expect()`, `panic!`, `todo!`, `unimplemented!`, `unreachable!`, raw indexing/slicing, or `process::exit`. Return `Result`/`Option` and handle every case.
- Use checked/saturating/wrapping arithmetic and `TryFrom`/`try_into` rather than `as` casts.
- Every `Cargo.toml` must include this lint config:

```toml
[lints.clippy]
pedantic = { level = "deny", priority = -1 }
nursery = { level = "deny", priority = -1 }
# DENY PANICS:
unwrap_used = "deny"
expect_used = "deny"
indexing_slicing = "deny"
arithmetic_side_effects = "deny"
unreachable = "deny"
unimplemented = "deny"
unchecked_time_subtraction = "deny"
todo = "deny"
string_slice = "deny"
panic_in_result_fn = "deny"
panic = "deny"
exit = "deny"
as_conversions = "deny"
```

## Odin
- Keep `.odin` files inside a `src/` directory and use `odin build src` accordingly.
- `Ada_Case` for types, `snake_case` for procs and variables, `SCREAMING_SNAKE_CASE` for constants, `lower_snake` for packages. Visibility is controlled by `@private`, not casing.
- Every `make`, `new`, `strings.clone`, or `fmt.aprintf` needs a matching `delete`/`free`.
- Allocations use `context.allocator` implicitly - don't add explicit allocator parameters to procedures unless the procedure needs to allocate into a different one than the caller's context.
- Prefer `context.temp_allocator` for short-lived allocations within a frame/request, and call `free_all(context.temp_allocator)` at the boundary.
- Wrap `main` with a tracking allocator in debug builds - see `mem.Tracking_Allocator`. 
- Use multiple return values with `ok` booleans, not exceptions: `value, ok := thing()`.
- Use `or_return` for error propagation, `or_else` for defaults.
- Prioritise `for x in slice` - not C-style index loops unless you need the index.
- Use `[dynamic]T`, `map[K]V`, and slices from the language; don't pull in containers from elsewhere.
- Use tagged unions via `union { ... }` plus `switch v in x` - not enum + void pointer.
- Don't reach for OOP patterns; this is data-oriented. No classes, prefer SoA when iterating hot data.
- Don't write generic abstractions speculatively - Odin has parametric polymorphism but the codebase prefers concrete types until duplication is real.
- Don't add Cargo/npm-style dependencies. Vendor anything external into `vendor/` or `shared/`.
- Prefer existing `vendor:` collection bindings (raylib, sdl3, glfw, etc.) over writing your own or pulling community bindings.
- Don't use dynamic array literals (`[dynamic]int{1,2,3}`) - they're disabled by default in current Odin.
- Run `odin test src` if `@(test)` procedures are present.
