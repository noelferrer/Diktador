---
type: module
created: 2026-04-27
updated: 2026-04-27
tags: [module, transcriber, whisperkit]
status: stable
---

# Transcriber

> Audio-file → text via WhisperKit. v1 ships local-only on `openai_whisper-base`; Groq sibling backend deferred.

## Purpose

Consumes 16 kHz mono PCM WAV files produced by [[modules/recorder]] and returns plain `String` transcripts. The module owns the WhisperKit lifecycle (model load, in-memory pipeline, transcription calls) and exposes a small `Transcriber` protocol so a future Groq backend can slot in as a sibling impl.

## Public API

`Transcriber` protocol — `state: TranscriberState`, `loadModel() async throws`, `transcribe(audioFileURL:) async throws -> String`. `WhisperKitTranscriber` is the v1 concrete impl. See [`modules/diktador-transcriber/README.md`](../../modules/diktador-transcriber/README.md) for the full surface.

## Design decisions

The decision to ship WhisperKit-only in v1, hard-code `openai_whisper-base`, eager-load on app launch, and copy transcripts to the clipboard as a stand-in for the output module is captured in [[decisions/transcriber-pipeline]]. The dual-backend framework lock that this module satisfies is in [[decisions/framework-choice]].

The `WhisperKitDriver` internal protocol mirrors the recorder's `AudioEngineDriver` test seam — only the `LiveWhisperKitDriver` source file imports WhisperKit, so unit tests run without touching the model or the network.

State machine:

```
.uninitialized → .loading → .ready ↔ .transcribing
                     │
                     └─→ .failed(...)   (sticky; restart to retry)
```

`.failed` is reached only via `loadModel()` failures — including the implicit `loadModel()` invoked from inside `transcribe()` when state is `.uninitialized` or `.loading`. Once sticky-failed, both `loadModel()` and `transcribe()` reject without re-attempting; restart the app to retry.

`loadModel` is idempotent and concurrent-safe via an in-flight `Task` reference; `transcribe` from `.uninitialized` drives `loadModel` implicitly.

## Dependencies

- `WhisperKit` from [argmaxinc/argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift), `from: 0.9.0`.
- Foundation.
- Network access for first-run model download (~140 MB for `openai_whisper-base`).
- No coupling to other Diktador modules at compile time. Consumes WAV files at any `URL` the caller provides.

## Open questions

- Model picker UX (settings module concern).
- Groq backend + dispatcher (follow-up PR).
- VAD / continuous-listening mode (deferred again, per the recorder ADR's deferral and the framework ADR).
- Cancellation of an in-flight transcription.
- Transcript history beyond the most-recent.
- Network reachability probe before download.
- WhisperKit version pinning policy (currently `from: 0.9.0` — no aggressive lock).
- **`prewarm: true` latency vs peak-memory trade-off** — accepted for v1; revisit when concrete latency measurements on user hardware exist.

## Related

- [[modules/recorder]] — produces the WAV files this module consumes.
- [[decisions/transcriber-pipeline]] — design rationale.
- [[decisions/framework-choice]] — parent ADR.
- [[decisions/recorder-capture-pipeline]] — sibling ADR; locks the WAV format.
