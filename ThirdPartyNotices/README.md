# Speech dependencies

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
