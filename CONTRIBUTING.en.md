# Contributing to JieJu

English · [简体中文](CONTRIBUTING.md)

Thank you for helping JieJu. We welcome code, documentation, tests, model-evaluation cases, and minimal reproduction files that are safe to redistribute.

## Before you start

1. Read [PRODUCT.md](PRODUCT.md), [ARCHITECTURE.md](ARCHITECTURE.md), and [TODO.md](TODO.md).
2. Multi-agent or automated development must also follow [AGENTS.md](AGENTS.md) and consult [HANDOFF.md](HANDOFF.md).
3. Search existing issues first. Open a discussion issue before making a substantial product or architecture change.
4. Keep each pull request focused on one clearly bounded problem. Avoid unrelated formatting or refactoring.
5. When changing public positioning, capability status, or setup instructions, update both `README.md` and `README.en.md`. Do not make performance, compatibility, or completion claims that cannot be verified.

## Development environment

For macOS development:

- macOS 14+
- Xcode 16+ / Swift 6
- Node.js 20+
- Ollama only for local-model integration or manual verification

Open `JieJu.xcodeproj` to run the macOS app. Run the complete macOS and shared test suite with:

```bash
./scripts/test-all.sh
```

UI tests require macOS Developer Mode. If they cannot run, state which tests did run, describe the environmental blocker, and provide manual verification steps in the pull request.

For Windows requirements and commands, follow [Apps/Windows/README.md](Apps/Windows/README.md). The standard Windows verification entry point is:

```powershell
.\scripts\test-windows.ps1
```

## Branches and commits

Use focused names such as `feature/<topic>`, `fix/<topic>`, or `docs/<topic>`. Commit messages follow concise Conventional Commits style:

```text
feat: add EPUB theme preview
fix: preserve reading position on reopen
test: cover malformed model response
docs: clarify local data storage
```

Do not rewrite another contributor's history. Never commit private books, API keys, personal paths, model output artifacts, or build directories.

## Architecture boundaries

- SwiftUI views do not call networking, Ollama, or persistence implementations directly.
- AI features go through `ReadingAI` or the relevant provider protocol; deterministic mocks are preferred in automated tests.
- Published fields in `Shared/Contracts` are versioned contracts. Breaking changes require a new version.
- New business logic needs unit tests; critical reading workflows should include UI coverage where practical.
- Before changing EPUB scripts, AI DTOs, persistence formats, or cross-platform messages, read [Docs/CROSS_PLATFORM.md](Docs/CROSS_PLATFORM.md).

## Model and EPUB reproduction material

- Model-quality reports should include input language, expected behavior, model name, and only the context necessary to reproduce the issue.
- Prefer original or freely redistributable minimal EPUB fixtures. If the source file cannot be shared, describe only the relevant OPF, CSS, and XHTML structure.
- Redact book titles, user names, file paths, API keys, private notes, and substantial copyrighted text from screenshots.

## Pull request checklist

- [ ] The change has clear user value and acceptance criteria.
- [ ] Relevant tests were added or updated and pass.
- [ ] The platform test script was run, or an environmental blocker is documented.
- [ ] Documentation, TODO items, and architecture decisions were updated when needed.
- [ ] No secrets, private documents, personal paths, or unrelated changes are included.
- [ ] AI-assisted contributions have been read and manually validated by the contributor.

Using AI tools does not reduce the value of a contribution, but contributors remain responsible for correctness, licensing, testing, privacy, and security.

## License

By contributing, you agree that your contribution is licensed under the project's [Apache License 2.0](LICENSE). Do not submit code or material that you do not have the right to provide under that license.
