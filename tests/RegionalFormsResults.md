# Regional transformation smoke check

2026-10-12, local Mac, Apple Foundation Models available. Seven samples used
fixed base translations and the production regional prompt with greedy sampling.
This isolates regional adaptation; it does not exercise Apple Translation or
measure iPhone latency. Native-speaker review is still required, and these samples
do not certify all 48 forms or preservation of every linguistic nuance.

| Requested form | Base expression | Observed result |
| --- | --- | --- |
| British English | I left my sneakers in the trunk. | I’ve left my trainers in the boot |
| Mexican Spanish | El ordenador está en el coche. | La computadora está en el carro |
| Chilean Spanish | El ordenador está en el coche. | El computador está en el auto |
| Hong Kong Cantonese | 我打车去机场。 | 我搭的士去機場 |
| British English | The elevator in my apartment building is broken. | The lift in my block is out of action |
| Chilean Spanish | He dejado el móvil en casa. | Dejé el celular en casa |
| Hong Kong Cantonese | 我没有钱。 | 我冇錢 |

Earlier prompts retained Spain's computer/car terms for Mexican and Chilean
Spanish, exaggerated British possessives, and left Mandarin taxi wording in
Cantonese. The final prompt requests neutral grammar and supplies small regional
usage cues. These are prompt examples, not substitutions applied to generated
text. Vocabulary cues were checked against ASALE's entries for
[computador](https://www.asale.org/damer/computador),
[carro](https://www.asale.org/damer/carro), and
[auto](https://www.asale.org/damer/auto), and the Cantonese Dictionary entry for
[的士](https://cantowords.com/dictionary/%E7%9A%84%E5%A3%AB).

The British result changes past simple to present perfect; grammatical adaptation
can affect nuance even when regional vocabulary is correct. No automated check
here proves semantic or dialect accuracy. Existing model-availability checks still
apply: on this Mac, Russian and Hindi locales are not advertised as supported.
