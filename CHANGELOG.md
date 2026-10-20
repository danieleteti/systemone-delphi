# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/) and the project follows [Semantic Versioning](https://semver.org/).

## [0.9.0] - 2026-10-20

First public version.

### Added
- `ISystemOneClient.Ask(state, questions)` with the question types `Choice`, `Score` and `Noul`, and the builders `TSO.Choice(id, instructions).Option(label, description)`, `TSO.Score` and `TSO.Noul`. A question is checked (two options at least, no empty or repeated label) before any request is sent.
- `TSystemOneClient`: the System One API (`POST /v1/systemone`), for TypeSafe Jev and for Ollama (0.35.1 or later). `Create(server, key, model)` has no defaults, so nothing assumes Jev. The key may be empty: then no `Authorization` header is sent.
- `TSystemOneLLMAdapter`: the same questions answered by any OpenAI-compatible chat model, with a strict JSON Schema, normalized probabilities, clamped `Noul`, and tolerance for JSON wrapped in a code fence.
- `SYSTEMONE_CLIENT_VERSION` constant.
- Offline test suite (36 checks, fake server), live test suite (9 checks, Ollama + `tev1:4b`), `tests\run_all.py`.
- `sample\Triage.dpr`.

### Known limits
- Not tried with the real Jev API (no key available), nor with Ollaya.
- The `box` question type is not supported.
- Built and tested with Delphi 12 and 13 on Win32 only.

[0.9.0]: https://github.com/danieleteti/systemone-delphi/releases/tag/v0.9.0
