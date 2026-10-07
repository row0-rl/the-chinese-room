# Third-party dependencies

FluidAudio is used under Apache-2.0; see `FluidAudio-Apache-2.0.txt`.

- FluidAudio: https://github.com/FluidInference/FluidAudio
  Revision: `5343241cd8a7576890e50925dec666bafc89d324`
Supertonic 3 model assets are downloaded from FluidInference's Core ML mirror.
The upstream model is distributed under the OpenRAIL-M license.

- Upstream: https://huggingface.co/Supertone/supertonic-3
- Core ML conversion: https://huggingface.co/FluidInference/supertonic-3-coreml

FluidAudio includes text normalization through NemoTextProcessing:
https://github.com/FluidInference/text-processing-rs

Downloaded assets retain their own provenance and license requirements.

Korean Revised Romanization uses a native Swift port derived from KOROMAN's
MIT-licensed pronunciation rules. See `KOROMAN-MIT.txt`.

Patrick Hand is bundled under the SIL Open Font License 1.1. See
`PatrickHand-OFL.txt` for the copyright notice and full license.

- Designer: Patrick Wagesreiter
- Source: https://github.com/google/fonts/tree/main/ofl/patrickhand
- File: `PatrickHand-Regular.ttf` (PostScript name: `PatrickHand-Regular`)
- SHA-256: `0f173b3e6cb6d1af25babf7f0057c5ac4ee11f9992b0469bb817e967ef4ad0fc`

Xiaolai is bundled under the SIL Open Font License 1.1. See
`Xiaolai-OFL.txt` for the copyright notices and full license.

- Authors: LXGW; derived from Nozomi Seto's SetoFont
- Source: https://github.com/lxgw/kose-font/releases/tag/v3.126
- File: `Xiaolai-Regular.ttf` (PostScript name: `Xiaolai`)
- SHA-256: `e2f68daf0e72777a8cf58bc83de1b98634b251e537ddbfca24b0ae50d1802da2`
- CJK text uses Xiaolai after Patrick Hand; other scripts and missing glyphs
  retain system fallbacks. This release lacks the modern Hangul syllable `썏`
  (U+C34F), so that syllable uses the system fallback as well.
