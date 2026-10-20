# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

## Project

Delphi client for System One models (typed questions in, answers with probabilities out). One unit, RTL only: `sources\SystemOne.Client.pas`.

- **Language:** Object Pascal (Delphi 12 and 13 tested, Win32)
- **License:** Apache 2.0
- **Version:** `SYSTEMONE_CLIENT_VERSION` in the unit, README badge and `CHANGELOG.md` must agree. Semantic Versioning; `0.x` minors may break.

## Layout

- `sources\SystemOne.Client.pas`: `ISystemOneClient`, `TSystemOneClient`, `TSystemOneLLMAdapter`, `TSO` builders.
- `tests\`: `SystemOneTest.dpr` (offline, against `fake_server.py`), `SystemOneLiveTest.dpr` (against Ollama), `run_all.py`.
- `sample\Triage.dpr`: the quickstart. Build it from inside `sample\` (the `in` clause path is relative).

## Tests

```bat
python tests\run_all.py            :: offline suite (36 checks)
python tests\run_all.py --live     :: plus live suite (needs Ollama >= 0.35.1 and `ollama pull tev1:4b`)
```

Say what was verified: "compiles", "the offline suite passes" (fake server, proves the client only) and "seen working" (live) are three different claims. The real Jev API has not been tried.

## Conventions

- The unit stays RTL-only, so it drops into any project, DelphiMVCFramework ones included. Code that needs another framework belongs in `sample\`, not in `sources\`.
- The caller owns `TSOResponse`. Interfaces for clients, so a client variable must be `ISystemOneClient`, never a class reference.
- Do not use nested braces inside a `{ }` comment: use `//`.
