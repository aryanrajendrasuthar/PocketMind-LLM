# Contributing to PocketMind

PocketMind is proprietary software. Contributions are by invitation only.

## Internal Contribution Guidelines

### Branch Naming

```
feature/<short-description>
fix/<short-description>
chore/<short-description>
docs/<short-description>
```

### Commit Message Format

```
<type>: <short summary in imperative mood>

<optional body — wrap at 72 chars>
```

Types: `feat`, `fix`, `chore`, `docs`, `test`, `perf`, `refactor`

### Pull Request Requirements

- All CI checks must pass (SwiftLint, build, unit tests, static analysis)
- No force-unwraps introduced
- No `print()` calls in production Swift files
- No hardcoded strings — use `Constants.swift`
- New public functions must have `///` doc comments
- Python changes must pass `flake8` and `mypy --strict`

### Code Review

All PRs require at least one review from the repository owner before merge.

### Testing

- Every new feature must include unit tests
- Bug fixes must include a regression test
- Classifier changes must update the 30-query test suite in `ClassifierTests/`

---

For questions: aryanrajendrasuthar@gmail.com
