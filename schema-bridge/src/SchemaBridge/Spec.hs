module SchemaBridge.Spec
  ( Declaration (..),
    Field (..),
    TypeReference (..),
    declarations,
  )
where

data Declaration
  = EnumDeclaration String [String]
  | RecordDeclaration String [Field]

data Field = Field
  { fieldName :: String,
    fieldType :: TypeReference
  }

data TypeReference
  = TString
  | TInt
  | TBoolean
  | TMaybe TypeReference
  | TArray TypeReference
  | TNamed String

declarations :: [Declaration]
declarations =
  [ EnumDeclaration "LessonStatus" ["Locked", "Available", "InProgress", "Completed"],
    EnumDeclaration "AuthProvider" ["Google", "Dev"],
    EnumDeclaration "ExerciseKind" ["MultipleChoice", "Cloze", "Ordering", "TrueFalse"],
    EnumDeclaration "KnowledgeDimension" ["Recognition", "MeaningRecall", "FormRecall", "UseInContext", "Collocation"],
    RecordDeclaration
      "UserSummary"
      [ Field "displayName" TString,
        Field "email" TString,
        Field "avatarUrl" (TMaybe TString),
        Field "provider" (TNamed "AuthProvider")
      ],
    RecordDeclaration
      "DevLoginOption"
      [ Field "email" TString,
        Field "displayName" TString
      ],
    RecordDeclaration
      "AuthConfig"
      [ Field "googleEnabled" TBoolean,
        Field "googleClientId" (TMaybe TString),
        Field "devLoginEnabled" TBoolean,
        Field "devLoginOptions" (TArray (TNamed "DevLoginOption"))
      ],
    RecordDeclaration
      "SessionSnapshot"
      [ Field "viewer" (TMaybe (TNamed "UserSummary")),
        Field "authConfig" (TNamed "AuthConfig")
      ],
    RecordDeclaration
      "LearnerProfile"
      [ Field "learnerName" TString,
        Field "xp" TInt,
        Field "streakDays" TInt,
        Field "completedLessons" TInt,
        Field "totalLessons" TInt
      ],
    RecordDeclaration
      "DashboardStats"
      [ Field "dueReviews" TInt,
        Field "currentUnitTitle" TString,
        Field "currentUnitProgressPercent" TInt,
        Field "accuracyPercent" TInt
      ],
    RecordDeclaration
      "LessonSummary"
      [ Field "lessonId" TString,
        Field "unitId" TString,
        Field "index" TInt,
        Field "title" TString,
        Field "subtitle" TString,
        Field "goal" TString,
        Field "xpReward" TInt,
        Field "exerciseCount" TInt,
        Field "status" (TNamed "LessonStatus"),
        Field "masteryPercent" TInt
      ],
    RecordDeclaration
      "UnitSummary"
      [ Field "unitId" TString,
        Field "index" TInt,
        Field "title" TString,
        Field "cefrBand" TString,
        Field "focus" TString,
        Field "lessonSummaries" (TArray (TNamed "LessonSummary")),
        Field "completedLessons" TInt,
        Field "totalLessons" TInt,
        Field "unlocked" TBoolean
      ],
    RecordDeclaration
      "ExercisePrompt"
      [ Field "exerciseId" TString,
        Field "lessonId" TString,
        Field "kind" (TNamed "ExerciseKind"),
        Field "prompt" TString,
        Field "promptDetail" (TMaybe TString),
        Field "choices" (TArray TString),
        Field "fragments" (TArray TString),
        Field "answerText" (TMaybe TString),
        Field "acceptableAnswers" (TArray TString),
        Field "translation" (TMaybe TString),
        Field "hint" (TMaybe TString),
        Field "explanation" TString
      ],
    RecordDeclaration
      "LessonDetail"
      [ Field "lesson" (TNamed "LessonSummary"),
        Field "narrative" TString,
        Field "tips" (TArray TString),
        Field "exercises" (TArray (TNamed "ExercisePrompt"))
      ],
    RecordDeclaration
      "ReviewSummary"
      [ Field "exerciseId" TString,
        Field "lessonId" TString,
        Field "lessonTitle" TString,
        Field "prompt" TString,
        Field "dueLabel" TString,
        Field "masteryPercent" TInt
      ],
    RecordDeclaration
      "VocabularyCard"
      [ Field "lexemeId" TString,
        Field "headword" TString,
        Field "partOfSpeech" TString,
        Field "cefrBand" TString,
        Field "lessonId" TString,
        Field "lessonTitle" TString,
        Field "definition" TString,
        Field "exampleSentence" TString,
        Field "translation" (TMaybe TString),
        Field "collocations" (TArray TString),
        Field "tags" (TArray TString),
        Field "masteryPercent" TInt,
        Field "dueLabel" TString
      ],
    RecordDeclaration
      "VocabularyReviewPrompt"
      [ Field "reviewId" TString,
        Field "lexemeId" TString,
        Field "dimension" (TNamed "KnowledgeDimension"),
        Field "prompt" TString,
        Field "promptDetail" (TMaybe TString),
        Field "choices" (TArray TString),
        Field "answerText" (TMaybe TString),
        Field "acceptableAnswers" (TArray TString),
        Field "hint" (TMaybe TString),
        Field "explanation" TString,
        Field "masteryPercent" TInt,
        Field "dueLabel" TString
      ],
    RecordDeclaration
      "VocabularyDashboard"
      [ Field "dueCount" TInt,
        Field "totalTracked" TInt,
        Field "averageMasteryPercent" TInt,
        Field "focusWords" (TArray (TNamed "VocabularyCard")),
        Field "reviewQueue" (TArray (TNamed "VocabularyReviewPrompt"))
      ],
    RecordDeclaration
      "VocabularyReviewSubmission"
      [ Field "reviewId" TString,
        Field "lexemeId" TString,
        Field "dimension" (TNamed "KnowledgeDimension"),
        Field "answerText" (TMaybe TString),
        Field "selectedChoice" (TMaybe TString)
      ],
    RecordDeclaration
      "VocabularyFeedback"
      [ Field "lexemeId" TString,
        Field "dimension" (TNamed "KnowledgeDimension"),
        Field "correct" TBoolean,
        Field "explanation" TString,
        Field "expectedAnswer" TString,
        Field "masteryPercent" TInt,
        Field "xpDelta" TInt,
        Field "nextReviewHours" TInt
      ],
    RecordDeclaration
      "VocabularyReviewResult"
      [ Field "feedback" (TNamed "VocabularyFeedback"),
        Field "profile" (TNamed "LearnerProfile"),
        Field "dashboard" (TNamed "VocabularyDashboard")
      ],
    RecordDeclaration
      "PlacementQuestion"
      [ Field "questionId" TString,
        Field "cefrBand" TString,
        Field "skill" TString,
        Field "prompt" TString,
        Field "promptDetail" (TMaybe TString),
        Field "choices" (TArray TString)
      ],
    RecordDeclaration
      "PlacementAnswer"
      [ Field "questionId" TString,
        Field "selectedChoice" (TMaybe TString),
        Field "answerText" (TMaybe TString)
      ],
    RecordDeclaration
      "PlacementSubmission"
      [ Field "answers" (TArray (TNamed "PlacementAnswer"))
      ],
    RecordDeclaration
      "AppBootstrap"
      [ Field "profile" (TNamed "LearnerProfile"),
        Field "stats" (TNamed "DashboardStats"),
        Field "recommendedLessonId" (TMaybe TString),
        Field "reviewQueue" (TArray (TNamed "ReviewSummary")),
        Field "vocabulary" (TNamed "VocabularyDashboard"),
        Field "units" (TArray (TNamed "UnitSummary"))
      ],
    RecordDeclaration
      "PlacementResult"
      [ Field "placedCefrBand" TString,
        Field "scorePercent" TInt,
        Field "xpAwarded" TInt,
        Field "completedLessonsDelta" TInt,
        Field "recommendedLessonId" (TMaybe TString),
        Field "bootstrap" (TNamed "AppBootstrap")
      ],
    RecordDeclaration
      "AttemptStart"
      [ Field "lessonId" TString
      ],
    RecordDeclaration
      "AttemptView"
      [ Field "attemptId" TString,
        Field "lesson" (TNamed "LessonSummary"),
        Field "narrative" TString,
        Field "tips" (TArray TString),
        Field "exercises" (TArray (TNamed "ExercisePrompt")),
        Field "currentIndex" TInt
      ],
    RecordDeclaration
      "AnswerSubmission"
      [ Field "exerciseId" TString,
        Field "answerText" (TMaybe TString),
        Field "selectedChoices" (TArray TString),
        Field "booleanAnswer" (TMaybe TBoolean)
      ],
    RecordDeclaration
      "AnswerFeedback"
      [ Field "exerciseId" TString,
        Field "correct" TBoolean,
        Field "explanation" TString,
        Field "expectedAnswer" TString,
        Field "masteryPercent" TInt,
        Field "xpDelta" TInt,
        Field "nextReviewHours" TInt
      ],
    RecordDeclaration
      "AttemptProgress"
      [ Field "attemptId" TString,
        Field "lessonId" TString,
        Field "answeredCount" TInt,
        Field "totalExercises" TInt,
        Field "correctCount" TInt,
        Field "lastFeedback" (TMaybe (TNamed "AnswerFeedback")),
        Field "finished" TBoolean
      ],
    RecordDeclaration
      "AttemptCompletion"
      [ Field "attemptId" TString,
        Field "lessonId" TString,
        Field "lessonCompleted" TBoolean,
        Field "xpAwarded" TInt,
        Field "profile" (TNamed "LearnerProfile"),
        Field "stats" (TNamed "DashboardStats"),
        Field "newlyUnlockedLessonId" (TMaybe TString)
      ],
    RecordDeclaration
      "GoogleAuthRequest"
      [ Field "credential" TString
      ],
    RecordDeclaration
      "DevLoginRequest"
      [ Field "email" TString
      ],
    RecordDeclaration
      "ApiError"
      [ Field "message" TString
      ]
  ]
