# Curriculum Source

The curriculum seed is authored as checked-in JSON. The backend loads it on
startup and reseeds the SQLite database when needed.

## File

- `curriculum/english-a2.json`

## Shape

```json
{
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
- `choices` is used by multiple-choice and true/false items.
- `fragments` is used by ordering exercises.
- `answerText` is the canonical answer for cloze items.
- `acceptableAnswers` is the answer key used by the backend checker.
- `translation`, `hint`, and `promptDetail` may be `null`.
- `explanation` should always exist and stay learner-facing.
