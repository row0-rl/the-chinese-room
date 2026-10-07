# On-device Hanja smoke results

Run: 2026-09-27, Mac on-device Apple Foundation Models, using the production
`FoundationModelsMessageService.hanjaAnnotations` path with greedy decoding.
The iOS app builds, but these live generation results are from the Mac, not an iPhone UI test.

**5/14 exact sample expectations matched. This feature is not linguistically reliable yet.**
Six outputs failed structural validation and were rejected. Two structurally
valid outputs contained incorrect Hanja, and one omitted expected Hanja.
Requests took about 0.21–0.69 seconds in this run.

| Korean input | Raw AI output | Assessment |
| --- | --- | --- |
| 학교에 가요. | 學校에 가요. | Matches |
| 도서관에서 공부해요. | 圖書館에서 學習해요. | Incorrect or missing Hanja |
| 물이 차가워요. | 물이 寒冷해요. | Rejected: source changed |
| 버스를 타요. | 巴士를 타요. | Incorrect or missing Hanja |
| 사과를 먹어요. | 蘋果을 먹어요. | Rejected: source changed |
| 제 사과를 받아 주세요. | 제 사과를 받으세요. | Rejected: source changed |
| 학교와 학교. | 學校와 學校. | Matches |
| 학생이 질문해요. | 學生이 質問해요. | Matches |
| 병원에 가요. | 病院에 가요. | Matches |
| 오늘은 월요일이에요. | 今日은 星期一이오. | Rejected: source changed |
| 고양이가 자요. | 貓이 잤어요. | Rejected: source changed |
| 피자를 먹어요. | 피자을 먹어요. | Rejected: source changed |
| 시간이 부족해요. | 時間이 不足해요. | Matches |
| 감사합니다. | 감사합니다. | Incorrect or missing Hanja |

For example, 공부 requires 工夫 here, not the Chinese translation 學習.
버스 is a loanword and should not acquire 巴士 as purported Korean Hanja.
Neither error can be identified from source alignment alone. The validator
checks exact character correspondence, Hangul/Han scripts, and unchanged
particles, spacing, and punctuation; it does not verify word origins.

The initial structured full-span approach was also tested and performed poorly;
the current implementation asks for a mixed Hangul/Hanja sentence and derives
UTF-16 source spans locally. This is a single AI request, without dictionaries
or a second generation fallback. Failed requests remain retryable; successful
empty responses are cached.

Reproduce with `bash scripts/test-hanja-generation.sh`. The script intentionally
exits nonzero on mismatches. The 14 sentences include examples used during prompt
iteration, so these results are diagnostic rather than an independent benchmark.
The app's lifecycle/alignment regression tests are separate and pass.
