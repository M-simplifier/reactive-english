# Curriculum Source

The curriculum seed is authored as checked-in JSON. The backend loads it on
startup and reseeds the SQLite database when needed.

## Files

- `curriculum/english-cefr-c2.json`: default A1-C2 seed used by the app
- `curriculum/english-a2.json`: legacy smaller seed retained for comparison

## Shape

```json
{
  "placementQuestions": [
    {
      "questionId": "placement-a1-1",
      "cefrBand": "A1",
      "skill": "greetings",
      "prompt": "Choose the best reply to: Hi, I'm Yuki.",
      "promptDetail": null,
      "choices": ["Nice to meet you.", "At seven o'clock."],
      "acceptableAnswers": ["Nice to meet you."],
      "explanation": "A1 checks basic social response."
    }
  ],
  "units": [
    {
      "unitId": "u1",
      "index": 1,
      "title": "Personal Info",
      "cefrBand": "A1",
      "focus": "Introductions, be, countries, family basics",
      "lessons": [
        {
          "lessonId": "u1-l1",
          "index": 1,
          "title": "Hello There",
          "subtitle": "Greetings and names",
          "goal": "Introduce yourself and ask for basic personal details.",
          "xpReward": 40,
          "narrative": "Short study note shown before the lesson begins.",
          "tips": ["Short tip one", "Short tip two"],
          "exercises": [
            {
              "exerciseId": "u1-l1-e1",
              "kind": "MultipleChoice",
              "prompt": "Choose the best reply.",
              "promptDetail": "A: Hi, I'm Yuki. ____",
              "choices": ["Nice to meet you.", "I am from Tokyo.", "At seven o'clock."],
              "fragments": [],
              "answerText": null,
              "acceptableAnswers": ["Nice to meet you."],
              "translation": "はじめまして。",
              "hint": "Think about introductions.",
              "explanation": "This is the standard reply after someone introduces themselves."
            }
          ]
        }
      ]
    }
  ]
}
```

## Authoring Rules

- Keep IDs stable and globally unique.
- Regenerate the default CEFR seed with `npm run curriculum:generate`.
- Keep placement answers out of the public API response; the backend stores
  `acceptableAnswers` only for scoring.
- `choices` is used by multiple-choice and true/false items.
- `fragments` is used by ordering exercises.
- `answerText` is the canonical answer for cloze items.
- `acceptableAnswers` is the answer key used by the backend checker.
- `translation`, `hint`, and `promptDetail` may be `null`.
- `explanation` should always exist and stay learner-facing.
