# On-device speech

The app uses two local speech paths. English, French, Korean, Spanish,
Portuguese, Italian, Japanese, Russian, Hindi, and Swedish use Supertonic 3 through FluidAudio
and Core ML. Mandarin uses Apple's installed system speech voice. Supertonic
produces WAV audio for `AVAudioPlayer` playback.

## Language routing

| Language | Engine | Configuration |
| --- | --- | --- |
| English | Supertonic 3 | Shared ANE-bucketed INT4 Core ML model |
| French | Supertonic 3 | Shared ANE-bucketed INT4 Core ML model |
| Korean | Supertonic 3 | Shared ANE-bucketed INT4 Core ML model |
| Spanish | Supertonic 3 | Shared ANE-bucketed INT4 Core ML model |
| Portuguese | Supertonic 3 | Shared ANE-bucketed INT4 Core ML model |
| Italian | Supertonic 3 | Shared ANE-bucketed INT4 Core ML model |
| Japanese | Supertonic 3 | Shared ANE-bucketed INT4 Core ML model |
| Russian | Supertonic 3 | Shared ANE-bucketed INT4 Core ML model |
| Hindi | Supertonic 3 | Shared ANE-bucketed INT4 Core ML model |
| Swedish | Supertonic 3 | Shared ANE-bucketed INT4 Core ML model |
| Mandarin | Apple system speech | Installed `AVSpeechSynthesisVoice` |

Supertonic exposes ten shared voice styles (`F1`–`F5` and `M1`–`M5`). The same
styles work across its ten configured languages. For Mandarin, settings list
all voices that `AVSpeechSynthesisVoice.speechVoices()` exposes and label their
reported quality as Default, Enhanced, or Premium. Automatic selection uses the
system's default Mandarin voice.

## Downloads and execution

FluidAudio downloads the Supertonic Core ML assets on first use. Later requests
reuse the app's Application Support cache and work offline. Mandarin availability
depends on the voices installed through iOS. The app removes assets belonging to
retired speech engines after upgrading.

Each speech runtime serializes synthesis and caches its last generated WAV.
Cancellation prevents stale generated audio from playing but cannot necessarily
interrupt a Core ML prediction already in progress.

## Validation

Launch a Debug build with `--speech-smoke-test` to synthesize all ten
Supertonic languages, verify playable WAV data and cache reuse, and verify
availability of the default Mandarin system voice. Generated files are saved under
`Documents/SpeechChecks`. Simulator timing does not establish iPhone performance
or Neural Engine placement.

## Sources

- FluidAudio: https://github.com/FluidInference/FluidAudio (Apache-2.0)
- Supertonic 3: https://huggingface.co/Supertone/supertonic-3 (OpenRAIL-M)
- Supertonic Core ML: https://huggingface.co/FluidInference/supertonic-3-coreml

Bundled attribution is in `ThirdPartyNotices`. Downloaded model assets retain
their own provenance and license requirements.
