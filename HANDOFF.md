# system_llm Handoff

Date: 2026-11-12
Workspace: `/Users/h.aboshhiwa/workspace/system_llm`

## Request

The package was audited from four perspectives: enthusiastic feature ideas, senior engineering risks, product management reaction, and a staged product plan. The next requested step was to delegate the 0.2.1 stabilisation work to Opus 5.5 High.

## Delegation Status

The delegation was attempted twice and did not complete:

1. The requested model identifier was rejected by the tool because the available identifier was `Claude Opus 5.5 (anthropic)`, not the requested Copilot vendor form.
2. A retry using `Claude Opus 5.5 (anthropic)` was rejected because the Anthropic API credit balance was too low.

No commit, tag, push, or publish was performed.

## Baseline Already Verified

Before the current partial patch:

- `flutter analyze`: no issues.
- Root `flutter test`: 118 tests passed.
- `example/flutter test`: 50 tests passed.
- `flutter pub publish --dry-run`: 0 warnings.
- Package dependencies were up to date apart from newer incompatible transitive versions.
- The package was published as `0.2.0` on pub.dev.
- Git tags existed only for `v0.1.0` and `v0.1.1`.

## Current Worktree

The worktree is dirty with 12 modified files. These edits are already present and must be reviewed rather than discarded:

- `pubspec.yaml`: version changed to `0.2.1`.
- `ios/system_llm.podspec`: version changed from `0.1.1` to `0.2.1`.
- `lib/src/remote/remote_model.dart`: structured-output retry flow changed to understand provider truncation state.
- `lib/src/remote/openai_compatible_model.dart`: provider response handling changed for token-limit completion signals.
- `lib/src/remote/anthropic_model.dart`: provider response handling changed for `max_tokens` stop signals.
- `test/remote/openai_compatible_model_test.dart`: tests added/updated for structured output and cutoff responses.
- `test/remote/anthropic_model_test.dart`: tests added for structured output and cutoff responses.
- `lib/src/method_channel_system_llm.dart`: on-device stream overlap is guarded with the existing `busy` error code; state is released on completion, failure, cancellation, and timeout.
- `test/method_channel_test.dart`: tests added for overlap rejection and restarting after completion, failure, cancellation, and timeout.
- `android/src/main/kotlin/shewa/tech/system_llm/SystemLlmPlugin.kt`: stream generation state was adjusted to protect against an old job clearing state for a newer stream.
- `ios/system_llm/Sources/system_llm/SystemLlmPlugin.swift`: audio-session state capture/restoration work was added.
- `example/ios/RunnerTests/RunnerTests.swift`: stale template test was replaced with tests for unknown methods, availability, and environment handling.

`git diff --check` passed after the current edits.

## Still To Do For 0.2.1

### Required implementation/review

- Review every current diff for correctness and public API compatibility.
- Confirm the structured-output cutoff behavior: an invalid cutoff response must not be retried; a cutoff response that happens to match the schema may still return successfully.
- Confirm the new stream tests do not leak the static stream state between tests or leave platform message handlers installed.
- Confirm Android compiles after the stream-job change.
- Confirm iOS compiles after the audio-session restoration change.
- Run all post-edit verification:
  - `flutter analyze`
  - root `flutter test`
  - `cd example && flutter test`
  - Android Kotlin unit tests
  - example Android debug build
  - example iOS simulator/debug build without code signing, where the local toolchain permits

### Missing release work

- Add a `0.2.1` entry at the top of `CHANGELOG.md` describing only the changes actually retained.
- Add a `.github/workflows` CI workflow for pushes to `main` and pull requests. It should run Dart analysis, root/example tests, Kotlin unit tests, Android debug build, and iOS build without signing. Use read-only `contents` permissions and no secrets.
- Add a short README platform-parity section covering:
  - iOS checks model locale; Android currently ignores locale for model generation.
  - Android reports `model_not_ready` for downloadable/downloading models and this version does not initiate the download.
  - iOS constrains structured decoding; Android prompts and validates with one retry.
  - `maxItems` is not consistently enforced across platforms/adapters.
  - streams ending at `maxTokens` currently complete normally.
  - the Android manifest adds `RECORD_AUDIO` to host apps, including apps that never call speech; document the `tools:node="remove"` opt-out.
- Update any release/tag metadata only after the owner reviews the diff. Do not publish from this handoff.

## Audit Findings Deferred To Later Releases

These were identified but intentionally excluded from the 0.2.1 patch:

- Android model download and progress reporting.
- A dedicated truncation exception code.
- `close()` on the public `LanguageModel` interface.
- Per-provider or revised `maxTokens` defaults for reasoning models.
- Separate cancellation APIs for generation and speech.
- Token-aware context budgeting for `OnDeviceModel`.
- Better diagnostics without forwarding private provider error text.
- Locale handling parity on Android.
- Consistent `maxItems` validation.
- macOS support.
- Native multi-turn sessions on iOS.
- Partial speech-result streaming.
- Usage/token accounting, sampling controls, tool calling, image input, and text-to-speech.
- CI and stronger native test coverage are required for release confidence, but were not present in the baseline.

## Important Existing Risks

- iOS cancel-then-immediate-restart may still report `busy` until the cancelled task unwinds. This was intentionally left unchanged because it needs device validation and is existing behavior.
- The Dart method-channel stream implementation uses a static `_streaming` flag. Review whether its lifecycle is robust when platform stream creation throws synchronously or when multiple `MethodChannelSystemLlm` instances are used.
- The Android and iOS native implementations remain difficult to validate without real AICore and Apple Intelligence devices.
- The podspec had been stale at `0.1.1`; ensure the final release metadata and git tag are synchronized before publishing.

## Suggested Resume Sequence

1. Inspect `git diff` and resolve any issues in the current patch.
2. Add the missing changelog, CI workflow, and README parity section.
3. Run focused remote and method-channel tests first.
4. Run full Dart analysis and both Flutter test suites.
5. Run native unit/build checks available locally.
6. Review the final diff and only then decide whether to tag or publish.

No files other than this handoff were created by this handoff task.
