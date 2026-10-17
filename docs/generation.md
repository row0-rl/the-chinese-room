# On-device message generation

Translation baseline forms use four sequential stages:

1. Apple Foundation Models generates an everyday source expression or normalizes learner input.
2. Apple Translation translates that expression.
3. Apple Foundation Models returns only the smallest independently explainable target chunks.
4. One Apple Foundation Models request glosses all validated chunks in sentence context.

Segmentation uses a raw text response with separators inserted between chunks,
using Apple’s permissiveContentTransformations mode. The separator is chosen to
avoid any occurrence in the input. The app splits the response and validates it;
no guided schema or JSON parsing is used for this step. Coverage and order
are validated before glossing. Punctuation is ignored when checking coverage;
original formatting is restored for display where spans match. Missing, changed,
duplicated, or reordered content fails validation. One correction request includes
the previous segmentation and the specific coverage error.

Glosses refer to stable chunk IDs; the app assembles them onto the fixed spans.
One repair request contains only missing or invalid IDs, the previous output,
validation errors, and full sentence context. Valid glosses are retained. A single
failed gloss therefore causes a single-chunk repair; several failures share one
repair batch. No parallel model calls are made. A normal message uses three AFM
calls and one Apple Translation call; retries add calls only where necessary.

The runtime serializes requests, propagates cancellation, and creates a fresh
session for each request. Breakdown failure leaves the completed source and
translation available, with no fabricated glosses. Cancellation still propagates.

Rooms select a language and regional origin/form for both sides. Source generation
uses the selected form's spelling, vocabulary, grammar, and writing system.
Apple Translation receives the selected locales. For target forms outside the translation baselines,
one plain-text Foundation Models transformation adapts the translation to the
selected form before segmentation; invalid or empty output gets one repair attempt.
Failed adaptation fails the card rather than silently returning another form.
Chinese script conversion is enforced locally before segmentation.

Mandarin–Cantonese pairings use a direct on-device text transformation because
Apple Translation rejects these pairings as the same base language. Cantonese
uses the available Chinese writing model and explicit Cantonese instructions;
this is experimental prompted generation, not advertised Cantonese model support.
Regional spelling/wording and dialect correctness require native-speaker review
and target-iPhone checks. Successful structural checks do not prove these qualities.
Small prompt usage cues ground British English, Mexican and Chilean Spanish, and
vernacular Cantonese after live checks exposed weak region-only prompting; these
are examples, not text substitutions. See [observed results](../tests/RegionalFormsResults.md).
The voice catalog remains unchanged; new forms reuse existing language voices.

Guided generation and validation do not establish linguistic correctness or ideal
chunk granularity. Optional usage examples remain disabled. Message history and the last viewed card
are persisted separately for each saved Room (directional language pair).

Source generation and glossing use SystemLanguageModel.default with native guided
generation and default guardrails. Segmentation and regional adaptation use permissive text
transformation; the model can still refuse, and gloss generation may still trigger
default guardrails. No bundled
model, external Swift package, custom tokenizer, or raw JSON parsing is required.
Debug builds log generated segmentation and glosses plus validation failures.
Model-call failures also log a request ID, response type, exact instructions and
prompt, error details, and guardrail/refusal debug descriptions and metadata.
These diagnostics are omitted in release builds. Metadata is whatever the system
provides; it does not guarantee access to blocked text or identify whether the
input or output triggered a guardrail.

Build with Xcode 27 using bash scripts/build-and-launch.sh. The project targets
iOS 27. Apple Intelligence must be available, enabled, and ready, with the selected
languages supported. The SwiftUI translation host presents system download consent
for Apple Translation language assets when necessary.

See [tests](../tests/README.md). Mac smoke tests do not measure iPhone performance.
