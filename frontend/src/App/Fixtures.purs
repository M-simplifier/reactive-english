module App.Fixtures
  ( completeAttempt
  , initialBootstrap
  , loadBootstrap
  , loadLessonDetail
  , newDemoStore
  , startAttempt
  , submitAnswer
  ) where

import Prelude
  ( bind
  , discard
  , div
  , map
  , max
  , min
  , mod
  , otherwise
  , pure
  , show
  , (&&)
  , (*)
  , (+)
  , (-)
  , (/=)
  , (<$>)
  , (<=)
  , (<>)
  , (==)
  , (>=)
  , (>>>)
  , (||)
  )

import App.Schema.Generated
  ( AnswerSubmission
  , AppBootstrap
  , AttemptCompletion
  , AttemptProgress
  , AttemptView
  , ExerciseKind(..)
  , ExercisePrompt
  , KnowledgeDimension(..)
  , LessonDetail
  , LessonStatus(..)
  , LessonSummary
  , UnitSummary
  )
import Control.Alt ((<|>))
import Data.Array as Array
import Data.Maybe (Maybe(..), fromMaybe)
import Data.String (joinWith)
import Data.String.Common (toLower, trim)
import Effect (Effect)
import Effect.Exception (throw)
import Effect.Ref as Ref

type DemoAttemptState =
  { attemptId :: String
  , detail :: LessonDetail
  , answeredCount :: Int
  , correctCount :: Int
  , xpAwarded :: Int
  }

type DemoStore =
  { bootstrap :: AppBootstrap
  , lessons :: Array LessonDetail
  , attempts :: Array DemoAttemptState
  , nextAttemptId :: Int
  }

newDemoStore :: Effect (Ref.Ref DemoStore)
newDemoStore = Ref.new initialDemoStore

loadBootstrap :: Ref.Ref DemoStore -> Effect AppBootstrap
loadBootstrap ref = _.bootstrap <$> Ref.read ref

loadLessonDetail :: Ref.Ref DemoStore -> String -> Effect LessonDetail
loadLessonDetail ref lessonId = do
  store <- Ref.read ref
  case Array.find (\detail -> detail.lesson.lessonId == lessonId) store.lessons of
    Just detail -> pure detail
    Nothing -> throw ("Unknown lesson fixture: " <> lessonId)

startAttempt :: Ref.Ref DemoStore -> String -> Effect AttemptView
startAttempt ref lessonId = do
  store <- Ref.read ref
  detail <- loadLessonDetail ref lessonId
  let
    attemptId = "demo-attempt-" <> show store.nextAttemptId
    presentedDetail =
      detail { exercises = shuffleDemoOrderingExercises store.nextAttemptId detail.exercises }
    attemptState =
      { attemptId
      , detail: presentedDetail
      , answeredCount: 0
      , correctCount: 0
      , xpAwarded: 0
      }
    nextStore =
      store
        { attempts = store.attempts <> [ attemptState ]
        , nextAttemptId = store.nextAttemptId + 1
        }
  Ref.write nextStore ref
  pure
    { attemptId
    , lesson: presentedDetail.lesson
    , narrative: presentedDetail.narrative
    , tips: presentedDetail.tips
    , exercises: presentedDetail.exercises
    , currentIndex: 0
    }

shuffleDemoOrderingExercises :: Int -> Array ExercisePrompt -> Array ExercisePrompt
shuffleDemoOrderingExercises attemptSeed =
  Array.mapWithIndex \exerciseIndex exercise ->
    if exercise.kind == Ordering then
      exercise { fragments = rotateFragments (attemptSeed + exerciseIndex) exercise.fragments }
    else
      exercise

rotateFragments :: Int -> Array String -> Array String
rotateFragments seed fragments =
  let
    fragmentCount = Array.length fragments
  in
    if fragmentCount <= 1 then
      fragments
    else
      let
        offset = 1 + (seed `mod` (fragmentCount - 1))
      in
        Array.drop offset fragments <> Array.take offset fragments

submitAnswer :: Ref.Ref DemoStore -> String -> AnswerSubmission -> Effect AttemptProgress
submitAnswer ref attemptId submission = do
  store <- Ref.read ref
  attempt <- requireAttempt attemptId store.attempts
  exercise <- currentExercise attempt
  let
    correct = matchesSubmission exercise submission
    xpDelta = if correct then 12 else 3
    feedback =
      { exerciseId: exercise.exerciseId
      , correct
      , explanation: exercise.explanation
      , expectedAnswer: expectedAnswer exercise
      , masteryPercent: if correct then 92 else 48
      , xpDelta
      , nextReviewHours: if correct then 24 else 6
      }
    answeredCount = attempt.answeredCount + 1
    correctCount = attempt.correctCount + if correct then 1 else 0
    totalExercises = Array.length attempt.detail.exercises
    finished = answeredCount >= totalExercises
    updatedAttempt =
      attempt
        { answeredCount = answeredCount
        , correctCount = correctCount
        , xpAwarded = attempt.xpAwarded + xpDelta
        }
    updatedAttempts = replaceAttempt updatedAttempt store.attempts
  Ref.write (store { attempts = updatedAttempts }) ref
  pure
    { attemptId
    , lessonId: attempt.detail.lesson.lessonId
    , answeredCount
    , totalExercises
    , correctCount
    , lastFeedback: Just feedback
    , finished
    }

completeAttempt :: Ref.Ref DemoStore -> String -> Effect AttemptCompletion
completeAttempt ref attemptId = do
  store <- Ref.read ref
  attempt <- requireAttempt attemptId store.attempts
  let
    totalExercises = Array.length attempt.detail.exercises
    fullyCorrect = attempt.correctCount == totalExercises
    accuracy = if totalExercises == 0 then 0 else div (attempt.correctCount * 100) totalExercises
    bonusXp = if fullyCorrect then 8 else 0
    xpAwarded = attempt.xpAwarded + bonusXp
    completion = patchBootstrapForCompletion attempt.detail.lesson.lessonId xpAwarded accuracy store.bootstrap
    updatedStore =
      store
        { bootstrap = completion.bootstrap
        , attempts = Array.filter (\entry -> entry.attemptId /= attemptId) store.attempts
        }
  Ref.write updatedStore ref
  pure completion.response

initialBootstrap :: AppBootstrap
initialBootstrap =
  { profile:
      { learnerName: "Learner"
      , xp: 128
      , streakDays: 4
      , completedLessons: 1
      , totalLessons: 4
      }
  , stats:
      { dueReviews: 2
      , currentUnitTitle: "Daily English"
      , currentUnitProgressPercent: 50
      , accuracyPercent: 82
      }
  , recommendedLessonId: Just dailyRhythm.lessonId
  , reviewQueue:
      [ { exerciseId: "greet-2"
        , lessonId: greetings.lessonId
        , lessonTitle: greetings.title
        , prompt: "How do you do? is a formal greeting."
        , dueLabel: "Due now"
        , masteryPercent: 62
        }
      , { exerciseId: "daily-2"
        , lessonId: dailyRhythm.lessonId
        , lessonTitle: dailyRhythm.title
        , prompt: "Complete: She ___ to work by train."
        , dueLabel: "Later today"
        , masteryPercent: 48
        }
      ]
  , vocabulary:
      { dueCount: 2
      , totalTracked: 3
      , averageMasteryPercent: 34
      , focusWords:
          [ { lexemeId: "lex-routine"
            , headword: "routine"
            , partOfSpeech: "noun"
            , cefrBand: "A1-A2"
            , lessonId: dailyRhythm.lessonId
            , lessonTitle: dailyRhythm.title
            , definition: "A usual set of actions you do regularly."
            , exampleSentence: "My morning routine is simple."
            , translation: Just "usual actions"
            , collocations: [ "morning routine", "daily routine" ]
            , tags: [ "habits", "time" ]
            , masteryPercent: 30
            , dueLabel: "New word"
            }
          , { lexemeId: "lex-greeting"
            , headword: "Nice to meet you"
            , partOfSpeech: "phrase"
            , cefrBand: "A1"
            , lessonId: greetings.lessonId
            , lessonTitle: greetings.title
            , definition: "A polite phrase for a first meeting."
            , exampleSentence: "Nice to meet you, Aiko."
            , translation: Just "first meeting greeting"
            , collocations: [ "Nice to meet you too" ]
            , tags: [ "greeting" ]
            , masteryPercent: 72
            , dueLabel: "Due now"
            }
          ]
      , reviewQueue:
          [ { reviewId: "lex-routine:Recognition"
            , lexemeId: "lex-routine"
            , dimension: Recognition
            , prompt: "Which word matches this meaning?"
            , promptDetail: Just "A usual set of actions you do regularly."
            , choices: [ "ticket", "routine", "medicine" ]
            , answerText: Nothing
            , acceptableAnswers: [ "routine" ]
            , hint: Just "It is a noun."
            , explanation: "Recognition checks whether the meaning activates the right word."
            , masteryPercent: 30
            , dueLabel: "New word"
            }
          , { reviewId: "lex-greeting:FormRecall"
            , lexemeId: "lex-greeting"
            , dimension: FormRecall
            , prompt: "Type the word that fits this clue."
            , promptDetail: Just "A polite phrase for a first meeting."
            , choices: []
            , answerText: Nothing
            , acceptableAnswers: [ "Nice to meet you" ]
            , hint: Just "Nice to ____ you."
            , explanation: "Form recall checks whether you can produce the written phrase."
            , masteryPercent: 72
            , dueLabel: "Due now"
            }
          ]
      }
  , units:
      [ { unitId: "unit-daily-english"
        , index: 1
        , title: "Daily English"
        , cefrBand: "A1-A2"
        , focus: "routines, greetings, and short social exchanges"
        , lessonSummaries: [ greetings, dailyRhythm ]
        , completedLessons: 1
        , totalLessons: 2
        , unlocked: true
        }
      , { unitId: "unit-next-steps"
        , index: 2
        , title: "Next Steps"
        , cefrBand: "A2"
        , focus: "future plans and work coordination"
        , lessonSummaries: [ weekendPlans, workChat ]
        , completedLessons: 0
        , totalLessons: 2
        , unlocked: false
        }
      ]
  }

initialDemoStore :: DemoStore
initialDemoStore =
  { bootstrap: initialBootstrap
  , lessons:
      [ greetingsDetail
      , dailyRhythmDetail
      , weekendPlansDetail
      , workChatDetail
      ]
  , attempts: []
  , nextAttemptId: 1
  }

greetings :: LessonSummary
greetings =
  { lessonId: "lesson-greetings"
  , unitId: "unit-daily-english"
  , index: 1
  , title: "Warm Hellos"
  , subtitle: "formal and casual greetings"
  , goal: "Open a conversation naturally in everyday English."
  , xpReward: 28
  , exerciseCount: 3
  , status: Completed
  , masteryPercent: 100
  }

dailyRhythm :: LessonSummary
dailyRhythm =
  { lessonId: "lesson-daily-rhythm"
  , unitId: "unit-daily-english"
  , index: 2
  , title: "Daily Rhythm"
  , subtitle: "routines, time, and habits"
  , goal: "Talk about what you usually do during the day."
  , xpReward: 36
  , exerciseCount: 3
  , status: Available
  , masteryPercent: 48
  }

weekendPlans :: LessonSummary
weekendPlans =
  { lessonId: "lesson-weekend-plans"
  , unitId: "unit-next-steps"
  , index: 1
  , title: "Weekend Plans"
  , subtitle: "future arrangements"
  , goal: "Describe plans and invitations for the near future."
  , xpReward: 40
  , exerciseCount: 3
  , status: Locked
  , masteryPercent: 0
  }

workChat :: LessonSummary
workChat =
  { lessonId: "lesson-work-chat"
  , unitId: "unit-next-steps"
  , index: 2
  , title: "Work Chat"
  , subtitle: "simple workplace updates"
  , goal: "Handle short coordination messages at work."
  , xpReward: 42
  , exerciseCount: 3
  , status: Locked
  , masteryPercent: 0
  }

greetingsDetail :: LessonDetail
greetingsDetail =
  { lesson: greetings
  , narrative: "This lesson tunes your ear for polite openings, short intros, and the difference between formal and casual greetings."
  , tips:
      [ "Morning, afternoon, and evening greetings shift with the time of day."
      , "How do you do? is formal and usually answered with the same phrase."
      , "Nice to meet you is used for first meetings."
      ]
  , exercises:
      [ { exerciseId: "greet-1"
        , lessonId: greetings.lessonId
        , kind: MultipleChoice
        , prompt: "Choose the best greeting for 9 a.m."
        , promptDetail: Just "You meet a colleague in the office."
        , choices: [ "Good morning", "Good evening", "Good night" ]
        , fragments: []
        , answerText: Just "Good morning"
        , acceptableAnswers: [ "Good morning" ]
        , translation: Nothing
        , hint: Just "Think about the time of day."
        , explanation: "Good morning fits an office greeting before noon."
        }
      , { exerciseId: "greet-2"
        , lessonId: greetings.lessonId
        , kind: TrueFalse
        , prompt: "True or false: How do you do? is a formal greeting."
        , promptDetail: Nothing
        , choices: []
        , fragments: []
        , answerText: Just "true"
        , acceptableAnswers: [ "true" ]
        , translation: Nothing
        , hint: Just "It sounds more formal than Hi."
        , explanation: "How do you do? is formal and often appears in first introductions."
        }
      , { exerciseId: "greet-3"
        , lessonId: greetings.lessonId
        , kind: Cloze
        , prompt: "Complete the sentence: Nice to ___ you."
        , promptDetail: Nothing
        , choices: []
        , fragments: []
        , answerText: Just "meet"
        , acceptableAnswers: [ "meet" ]
        , translation: Just "Hajimemashite."
        , hint: Just "Use a simple verb."
        , explanation: "Nice to meet you is the standard phrase when meeting someone for the first time."
        }
      ]
  }

dailyRhythmDetail :: LessonDetail
dailyRhythmDetail =
  { lesson: dailyRhythm
  , narrative: "You are building the language of routines: simple present verbs, time phrases, and habitual actions."
  , tips:
      [ "Use the simple present for routines: I work, she works."
      , "Time phrases like at seven or after dinner help sequence a day."
      , "Third-person singular adds s: he walks, she goes."
      ]
  , exercises:
      [ { exerciseId: "daily-1"
        , lessonId: dailyRhythm.lessonId
        , kind: MultipleChoice
        , prompt: "Choose the natural sentence."
        , promptDetail: Just "You are describing your morning habit."
        , choices: [ "I drink coffee at seven.", "I drinking coffee at seven.", "I drinks coffee at seven." ]
        , fragments: []
        , answerText: Just "I drink coffee at seven."
        , acceptableAnswers: [ "I drink coffee at seven." ]
        , translation: Nothing
        , hint: Just "Use the base verb with I."
        , explanation: "Simple present with I takes the base verb: I drink."
        }
      , { exerciseId: "daily-2"
        , lessonId: dailyRhythm.lessonId
        , kind: Cloze
        , prompt: "Complete: She ___ to work by train."
        , promptDetail: Nothing
        , choices: []
        , fragments: []
        , answerText: Just "goes"
        , acceptableAnswers: [ "goes" ]
        , translation: Nothing
        , hint: Just "Third-person singular changes go."
        , explanation: "For she, the verb go becomes goes."
        }
      , { exerciseId: "daily-3"
        , lessonId: dailyRhythm.lessonId
        , kind: Ordering
        , prompt: "Build the sentence."
        , promptDetail: Just "Talk about the end of the school day."
        , choices: []
        , fragments: [ "We", "finish", "school", "at", "three." ]
        , answerText: Just "We finish school at three."
        , acceptableAnswers: [ "We finish school at three." ]
        , translation: Nothing
        , hint: Just "Subject first, then verb, then the time phrase."
        , explanation: "A clear routine sentence follows subject -> verb -> object -> time."
        }
      ]
  }

weekendPlansDetail :: LessonDetail
weekendPlansDetail =
  { lesson: weekendPlans
  , narrative: "This lesson moves from routine into planning: invitations, arrangements, and near-future language."
  , tips:
      [ "Going to is useful for plans you already decided."
      , "Would you like to...? opens polite invitations."
      , "Future time markers anchor the plan: tomorrow, on Saturday, next week."
      ]
  , exercises:
      [ { exerciseId: "weekend-1"
        , lessonId: weekendPlans.lessonId
        , kind: MultipleChoice
        , prompt: "Choose the best invitation."
        , promptDetail: Just "You want to invite a friend to a movie."
        , choices: [ "Would you like to watch a movie on Saturday?", "You like watch movie Saturday?", "Would you like watching a movie on Saturday?" ]
        , fragments: []
        , answerText: Just "Would you like to watch a movie on Saturday?"
        , acceptableAnswers: [ "Would you like to watch a movie on Saturday?" ]
        , translation: Nothing
        , hint: Just "Look for the polite invitation frame."
        , explanation: "Would you like to + verb is the natural invitation pattern."
        }
      , { exerciseId: "weekend-2"
        , lessonId: weekendPlans.lessonId
        , kind: Ordering
        , prompt: "Build the plan."
        , promptDetail: Just "Say that you are visiting your aunt tomorrow."
        , choices: []
        , fragments: [ "I", "am", "going", "to", "visit", "my", "aunt", "tomorrow." ]
        , answerText: Just "I am going to visit my aunt tomorrow."
        , acceptableAnswers: [ "I am going to visit my aunt tomorrow." ]
        , translation: Nothing
        , hint: Just "Use am going to for a decided plan."
        , explanation: "Going to signals a future plan that already exists."
        }
      , { exerciseId: "weekend-3"
        , lessonId: weekendPlans.lessonId
        , kind: TrueFalse
        , prompt: "True or false: I am going to stay home means you already have that plan."
        , promptDetail: Nothing
        , choices: []
        , fragments: []
        , answerText: Just "true"
        , acceptableAnswers: [ "true" ]
        , translation: Nothing
        , hint: Just "Going to is stronger than maybe."
        , explanation: "Going to usually points to a planned or expected future action."
        }
      ]
  }

workChatDetail :: LessonDetail
workChatDetail =
  { lesson: workChat
  , narrative: "Here you practice short coordination messages: updates, requests, and status checks in a calm workplace register."
  , tips:
      [ "Could you...? is a soft request."
      , "Still and already help with progress updates."
      , "Keep work chat short, direct, and polite."
      ]
  , exercises:
      [ { exerciseId: "work-1"
        , lessonId: workChat.lessonId
        , kind: Cloze
        , prompt: "Complete: Could you ___ me the file after lunch?"
        , promptDetail: Nothing
        , choices: []
        , fragments: []
        , answerText: Just "send"
        , acceptableAnswers: [ "send" ]
        , translation: Nothing
        , hint: Just "Use the base verb after could you."
        , explanation: "Could you is followed by the base form: send."
        }
      , { exerciseId: "work-2"
        , lessonId: workChat.lessonId
        , kind: MultipleChoice
        , prompt: "Choose the clearer progress update."
        , promptDetail: Just "You are still working on a report."
        , choices: [ "I am still working on the report.", "I still work on the report now.", "I am work still on the report." ]
        , fragments: []
        , answerText: Just "I am still working on the report."
        , acceptableAnswers: [ "I am still working on the report." ]
        , translation: Nothing
        , hint: Just "Still usually sits before the main -ing verb phrase."
        , explanation: "I am still working... is the natural present continuous update."
        }
      , { exerciseId: "work-3"
        , lessonId: workChat.lessonId
        , kind: TrueFalse
        , prompt: "True or false: Could you check this when you have a minute? is polite."
        , promptDetail: Nothing
        , choices: []
        , fragments: []
        , answerText: Just "true"
        , acceptableAnswers: [ "true" ]
        , translation: Nothing
        , hint: Just "It softens the request."
        , explanation: "Could you plus a time cushion like when you have a minute is polite and common."
        }
      ]
  }

currentExercise :: DemoAttemptState -> Effect ExercisePrompt
currentExercise attempt =
  case Array.index attempt.detail.exercises attempt.answeredCount of
    Just exercise -> pure exercise
    Nothing -> throw ("Attempt is already complete: " <> attempt.attemptId)

requireAttempt :: String -> Array DemoAttemptState -> Effect DemoAttemptState
requireAttempt attemptId attempts =
  case Array.find (\attempt -> attempt.attemptId == attemptId) attempts of
    Just attempt -> pure attempt
    Nothing -> throw ("Unknown attempt fixture: " <> attemptId)

replaceAttempt :: DemoAttemptState -> Array DemoAttemptState -> Array DemoAttemptState
replaceAttempt updated =
  map (\attempt -> if attempt.attemptId == updated.attemptId then updated else attempt)

expectedAnswer :: ExercisePrompt -> String
expectedAnswer exercise =
  fromMaybe (fromMaybe "" (Array.head exercise.acceptableAnswers)) exercise.answerText

matchesSubmission :: ExercisePrompt -> AnswerSubmission -> Boolean
matchesSubmission exercise submission =
  case exercise.kind of
    MultipleChoice ->
      case Array.head submission.selectedChoices of
        Just choice -> anyMatch [ choice ] exercise.acceptableAnswers
        Nothing -> false

    Cloze ->
      case submission.answerText of
        Just answer -> anyMatch [ answer ] exercise.acceptableAnswers
        Nothing -> false

    Ordering ->
      anyMatch [ joinWith " " submission.selectedChoices ] exercise.acceptableAnswers

    TrueFalse ->
      case submission.booleanAnswer of
        Just answer ->
          anyMatch [ if answer then "true" else "false" ] exercise.acceptableAnswers
        Nothing -> false

anyMatch :: Array String -> Array String -> Boolean
anyMatch submitted acceptable =
  Array.any
    (\candidate -> Array.any (\expected -> normalize candidate == normalize expected) acceptable)
    submitted

normalize :: String -> String
normalize =
  trim >>> toLower

patchBootstrapForCompletion
  :: String
  -> Int
  -> Int
  -> AppBootstrap
  -> { bootstrap :: AppBootstrap, response :: AttemptCompletion }
patchBootstrapForCompletion lessonId xpAwarded accuracy bootstrap =
  let
    alreadyCompleted =
      case Array.find (\lesson -> lesson.lessonId == lessonId) (Array.concatMap _.lessonSummaries bootstrap.units) of
        Just lesson -> lesson.status == Completed
        Nothing -> false
    newlyUnlockedLessonId = nextLockedLessonId bootstrap lessonId
    updatedUnits = map (patchUnit lessonId newlyUnlockedLessonId) bootstrap.units
    completedLessons =
      if alreadyCompleted then
        bootstrap.profile.completedLessons
      else
        min bootstrap.profile.totalLessons (bootstrap.profile.completedLessons + 1)
    updatedProfile =
      bootstrap.profile
        { xp = bootstrap.profile.xp + xpAwarded
        , completedLessons = completedLessons
        }
    leadUnit = fromMaybe (fromMaybe fallbackUnit (Array.head updatedUnits)) (Array.find _.unlocked updatedUnits)
    updatedStats =
      { dueReviews: bootstrap.stats.dueReviews
      , currentUnitTitle: leadUnit.title
      , currentUnitProgressPercent:
          if leadUnit.totalLessons == 0 then 0 else div (leadUnit.completedLessons * 100) leadUnit.totalLessons
      , accuracyPercent: div (bootstrap.stats.accuracyPercent + accuracy) 2
      }
    updatedBootstrap =
      bootstrap
        { profile = updatedProfile
        , stats = updatedStats
        , recommendedLessonId = newlyUnlockedLessonId <|> bootstrap.recommendedLessonId
        , units = updatedUnits
        }
    response =
      { attemptId: "complete-" <> lessonId
      , lessonId
      , lessonCompleted: true
      , xpAwarded
      , profile: updatedProfile
      , stats: updatedStats
      , newlyUnlockedLessonId
      }
  in
    { bootstrap: updatedBootstrap, response }
  where
  fallbackUnit =
    { unitId: "fallback"
    , index: 0
    , title: "Study Path"
    , cefrBand: "A1"
    , focus: ""
    , lessonSummaries: []
    , completedLessons: 0
    , totalLessons: 0
    , unlocked: true
    }

patchUnit :: String -> Maybe String -> UnitSummary -> UnitSummary
patchUnit lessonId unlockedLessonId unit =
  let
    updatedLessons = map patchLesson unit.lessonSummaries
    completedLessons = Array.length (Array.filter (\lesson -> lesson.status == Completed) updatedLessons)
    unlocked = unit.unlocked || Array.any (\lesson -> lesson.status /= Locked) updatedLessons
  in
    unit
      { lessonSummaries = updatedLessons
      , completedLessons = completedLessons
      , unlocked = unlocked
      }
  where
  patchLesson lesson
    | lesson.lessonId == lessonId =
        lesson { status = Completed, masteryPercent = max lesson.masteryPercent 100 }
    | Just lesson.lessonId == unlockedLessonId && lesson.status == Locked =
        lesson { status = Available }
    | otherwise =
        lesson

nextLockedLessonId :: AppBootstrap -> String -> Maybe String
nextLockedLessonId bootstrap lessonId =
  let
    orderedLessons = Array.concatMap _.lessonSummaries bootstrap.units
  in
    case Array.findIndex (\lesson -> lesson.lessonId == lessonId) orderedLessons of
      Just currentIndex ->
        case Array.index orderedLessons (currentIndex + 1) of
          Just nextLesson | nextLesson.status == Locked -> Just nextLesson.lessonId
          _ -> Nothing
      Nothing -> Nothing
