module Test.App.Model
  ( run
  ) where

import Prelude (Unit, discard, (+), (/=), (&&), (==), (>>=))

import App.Fixtures (initialBootstrap)
import App.Model
  ( AppState
  , AuthState(..)
  , Command(..)
  , DataSource(..)
  , LoadState(..)
  , Msg(..)
  , PlacementState(..)
  , PreviewState(..)
  , SessionState(..)
  , VocabularyState(..)
  , buildPlacementAnswer
  , buildSubmission
  , buildVocabularySubmission
  , initialState
  , update
  )
import App.Schema.Generated
  ( AttemptView
  , AuthProvider(..)
  , ExerciseKind(..)
  , KnowledgeDimension(..)
  , LessonStatus(..)
  , LessonSummary
  , PlacementQuestion
  , PlacementResult
  , SessionSnapshot
  , VocabularyReviewPrompt
  )
import Data.Array as Array
import Data.Maybe (Maybe(..), fromMaybe)
import Effect (Effect)
import Test.Assert (assert)

run :: Effect Unit
run = do
  testStartupDispatch
  testSignedOutSessionSkipsBootstrap
  testSignedInSessionLoadsBootstrap
  testBootstrapSelectsDefaultUnit
  testChoiceSubmission
  testClozeSubmissionTrimsText
  testOrderingSubmissionUsesPickedFragments
  testTrueFalseSubmission
  testCheckAnswerRequiresDraft
  testAdvanceAfterFeedbackFinishesLesson
  testCompletionUnlocksNextLesson
  testLogoutDispatchesAndSignedOutSnapshotResetsState
  testStartVocabularyReviewOpensQueuedPrompt
  testVocabularyChoiceSubmission
  testSharedCheckAnswerRoutesActiveVocabularySession
  testVocabularyFeedbackPatchesDashboard
  testAdvanceVocabularyReviewClosesAfterLastCard
  testStartPlacementDispatchesLoad
  testPlacementChoiceBuildsSubmission
  testPlacementResultPatchesBootstrap

testStartupDispatch :: Effect Unit
testStartupDispatch = do
  let result = update AppStarted initialState
  assert (case Array.head result.commands of
    Just LoadSessionSnapshot -> true
    _ -> false)

testSignedOutSessionSkipsBootstrap :: Effect Unit
testSignedOutSessionSkipsBootstrap = do
  let result = update (SessionSnapshotLoaded signedOutSession) initialState
  assert (Array.null result.commands)
  assert (case result.state.bootstrap of
    NotAsked -> true
    _ -> false)

testSignedInSessionLoadsBootstrap :: Effect Unit
testSignedInSessionLoadsBootstrap = do
  let result = update (SessionSnapshotLoaded signedInSession) initialState
  assert (case Array.head result.commands of
    Just LoadBootstrap -> true
    _ -> false)
  assert (case result.state.bootstrap of
    Loading -> true
    _ -> false)

testBootstrapSelectsDefaultUnit :: Effect Unit
testBootstrapSelectsDefaultUnit = do
  let
    authed = update (SessionSnapshotLoaded signedInSession) initialState
    result = update (BootstrapLoaded LiveBackend initialBootstrap) authed.state
  assert (result.state.selectedUnitId == Just "unit-daily-english")

testChoiceSubmission :: Effect Unit
testChoiceSubmission = do
  let
    exercise =
      { exerciseId: "exercise-1"
      , lessonId: "lesson-1"
      , kind: MultipleChoice
      , prompt: "Choose the correct sentence."
      , promptDetail: Nothing
      , choices: [ "A", "B" ]
      , fragments: []
      , answerText: Just "B"
      , acceptableAnswers: [ "B" ]
      , translation: Nothing
      , hint: Nothing
      , explanation: "B is correct."
      }
    lesson =
      { lessonId: "lesson-1"
      , unitId: "unit-1"
      , index: 1
      , title: "Choice Test"
      , subtitle: "single prompt"
      , goal: "Choose one answer."
      , xpReward: 20
      , exerciseCount: 1
      , status: Available
      , masteryPercent: 0
      }
    attempt =
      { attemptId: "attempt-1"
      , lesson
      , narrative: "Narrative"
      , tips: []
      , exercises: [ exercise ]
      , currentIndex: 0
      }
    opened = update (AttemptLoaded LiveBackend attempt) authedDashboard.state
    selected = update (ChooseChoice 1) opened.state
  assert (case selected.state.session of
    SessionActive session ->
      case buildSubmission session of
        Just submission -> submission.selectedChoices == [ "B" ]
        Nothing -> false
    _ -> false)
  let checked = update CheckAnswer selected.state
  assert (case Array.head checked.commands of
    Just (SendAnswer "attempt-1" submission) -> submission.selectedChoices == [ "B" ]
    _ -> false)

testClozeSubmissionTrimsText :: Effect Unit
testClozeSubmissionTrimsText = do
  let
    opened = update (AttemptLoaded LiveBackend clozeAttempt) authedDashboard.state
    submitted = update (SubmitTextAnswer "  are  ") opened.state
  assert (case Array.head submitted.commands of
    Just (SendAnswer "attempt-cloze" submission) -> submission.answerText == Just "are"
    _ -> false)

testOrderingSubmissionUsesPickedFragments :: Effect Unit
testOrderingSubmissionUsesPickedFragments = do
  let
    opened = update (AttemptLoaded LiveBackend orderingAttempt) authedDashboard.state
    pickedI = update (OrderingPick 1) opened.state
    pickedAm = update (OrderingPick 3) pickedI.state
    checked = update CheckAnswer pickedAm.state
  assert (case Array.head checked.commands of
    Just (SendAnswer "attempt-ordering" submission) -> submission.selectedChoices == [ "I", "am" ]
    _ -> false)

testTrueFalseSubmission :: Effect Unit
testTrueFalseSubmission = do
  let
    opened = update (AttemptLoaded LiveBackend trueFalseAttempt) authedDashboard.state
    selected = update (ChooseBoolean false) opened.state
    checked = update CheckAnswer selected.state
  assert (case Array.head checked.commands of
    Just (SendAnswer "attempt-boolean" submission) -> submission.booleanAnswer == Just false
    _ -> false)

testCheckAnswerRequiresDraft :: Effect Unit
testCheckAnswerRequiresDraft = do
  let opened = update (AttemptLoaded LiveBackend singleChoiceAttempt) authedDashboard.state
      checked = update CheckAnswer opened.state
  assert (Array.null checked.commands)
  assert (case checked.state.session of
    SessionActive session -> session.message == Just "Choose or type an answer before checking."
    _ -> false)

testAdvanceAfterFeedbackFinishesLesson :: Effect Unit
testAdvanceAfterFeedbackFinishesLesson = do
  let
    opened = update (AttemptLoaded LiveBackend singleChoiceAttempt) authedDashboard.state
    progressed =
      update
        ( AnswerProgressLoaded
            LiveBackend
            { attemptId: "attempt-1"
            , lessonId: "lesson-1"
            , answeredCount: 1
            , totalExercises: 1
            , correctCount: 1
            , lastFeedback:
                Just
                  { exerciseId: "exercise-1"
                  , correct: true
                  , explanation: "B is correct."
                  , expectedAnswer: "B"
                  , masteryPercent: 100
                  , xpDelta: 5
                  , nextReviewHours: 24
                  }
            , finished: true
            }
        )
        opened.state
    advanced = update AdvanceAfterFeedback progressed.state
  assert (case Array.head advanced.commands of
    Just (FinishAttempt "attempt-1" "lesson-1") -> true
    _ -> false)
  assert (case advanced.state.session of
    SessionActive session -> session.submitting
    _ -> false)

testCompletionUnlocksNextLesson :: Effect Unit
testCompletionUnlocksNextLesson = do
  let
    completed =
      update
        ( CompletionLoaded
            LiveBackend
            { attemptId: "attempt-2"
            , lessonId: "lesson-daily-rhythm"
            , lessonCompleted: true
            , xpAwarded: 36
            , profile: initialBootstrap.profile
            , stats: initialBootstrap.stats
            , newlyUnlockedLessonId: Just "lesson-weekend-plans"
            }
        )
        authedDashboard.state
  assert (case completed.state.session of
    SessionClosed -> true
    _ -> false)
  assert (case completed.state.preview of
    PreviewClosed -> true
    _ -> false)
  assert (case completed.state.bootstrap of
    Loaded bootstrap ->
      case Array.find (\unit -> unit.unitId == "unit-next-steps") bootstrap.units >>= \unit ->
        Array.find (\lesson -> lesson.lessonId == "lesson-weekend-plans") unit.lessonSummaries of
        Just lesson -> lesson.status == Available
        Nothing -> false
    _ -> false)

testLogoutDispatchesAndSignedOutSnapshotResetsState :: Effect Unit
testLogoutDispatchesAndSignedOutSnapshotResetsState = do
  let requested = update RequestLogout authedDashboard.state
  assert (case Array.head requested.commands of
    Just Logout -> true
    _ -> false)
  assert (case requested.state.auth of
    AuthReady flow -> flow.busy && flow.message == Just "Signing out..."
    _ -> false)
  let completed = update (AuthActionCompleted signedOutSession) requested.state
  assert (Array.null completed.commands)
  assert (case completed.state.bootstrap of
    NotAsked -> true
    _ -> false)
  assert (case completed.state.session of
    SessionClosed -> true
    _ -> false)

testStartVocabularyReviewOpensQueuedPrompt :: Effect Unit
testStartVocabularyReviewOpensQueuedPrompt = do
  let result = update StartVocabularyReview authedDashboard.state
  assert (Array.null result.commands)
  assert (case result.state.vocabularySession of
    VocabularyActive session -> session.currentIndex == 0
    _ -> false)

testVocabularyChoiceSubmission :: Effect Unit
testVocabularyChoiceSubmission = do
  let
    opened = update StartVocabularyReview authedDashboard.state
    picked = update (ChooseVocabularyChoice 1) opened.state
    checked = update CheckVocabularyAnswer picked.state
  assert (case picked.state.vocabularySession of
    VocabularyActive session ->
      case buildVocabularySubmission session of
        Just submission -> submission.selectedChoice == Just "routine"
        Nothing -> false
    _ -> false)
  assert (case Array.head checked.commands of
    Just (SendVocabularyReview submission) -> submission.lexemeId == "lex-routine" && submission.selectedChoice == Just "routine"
    _ -> false)

testSharedCheckAnswerRoutesActiveVocabularySession :: Effect Unit
testSharedCheckAnswerRoutesActiveVocabularySession = do
  let
    opened = update StartVocabularyReview authedDashboard.state
    picked = update (ChooseVocabularyChoice 1) opened.state
    checked = update CheckAnswer picked.state
  assert (case Array.head checked.commands of
    Just (SendVocabularyReview submission) -> submission.lexemeId == "lex-routine" && submission.selectedChoice == Just "routine"
    _ -> false)

testVocabularyFeedbackPatchesDashboard :: Effect Unit
testVocabularyFeedbackPatchesDashboard = do
  let
    opened = update StartVocabularyReview authedDashboard.state
    reviewed =
      update
        ( VocabularyReviewLoaded
            LiveBackend
            { feedback:
                { lexemeId: "lex-routine"
                , dimension: Recognition
                , correct: true
                , explanation: "Recognition checks whether the meaning activates the right word."
                , expectedAnswer: "routine"
                , masteryPercent: 48
                , xpDelta: 2
                , nextReviewHours: 18
                }
            , profile: initialBootstrap.profile { xp = initialBootstrap.profile.xp + 2 }
            , dashboard: initialBootstrap.vocabulary { dueCount = 1, averageMasteryPercent = 40 }
            }
        )
        opened.state
  assert (case reviewed.state.bootstrap of
    Loaded bootstrap -> bootstrap.profile.xp == initialBootstrap.profile.xp + 2 && bootstrap.vocabulary.dueCount == 1
    _ -> false)
  assert (case reviewed.state.vocabularySession of
    VocabularyActive session -> session.feedback /= Nothing
    _ -> false)

testAdvanceVocabularyReviewClosesAfterLastCard :: Effect Unit
testAdvanceVocabularyReviewClosesAfterLastCard = do
  let
    oneCardBootstrap =
      initialBootstrap { vocabulary = initialBootstrap.vocabulary { reviewQueue = [ fromMaybePrompt ] } }
    withOneCard = authedDashboard.state { bootstrap = Loaded oneCardBootstrap }
    opened = update StartVocabularyReview withOneCard
    reviewed =
      update
        ( VocabularyReviewLoaded
            LiveBackend
            { feedback:
                { lexemeId: "lex-routine"
                , dimension: Recognition
                , correct: true
                , explanation: "Recognition checks whether the meaning activates the right word."
                , expectedAnswer: "routine"
                , masteryPercent: 48
                , xpDelta: 2
                , nextReviewHours: 18
                }
            , profile: initialBootstrap.profile
            , dashboard: oneCardBootstrap.vocabulary { reviewQueue = [] }
            }
        )
        opened.state
    advanced = update AdvanceVocabularyReview reviewed.state
  assert (case advanced.state.vocabularySession of
    VocabularyClosed -> true
    _ -> false)

testStartPlacementDispatchesLoad :: Effect Unit
testStartPlacementDispatchesLoad = do
  let result = update StartPlacementTest authedDashboard.state
  assert (case Array.head result.commands of
    Just LoadPlacementQuestions -> true
    _ -> false)
  assert (case result.state.placementSession of
    PlacementLoading -> true
    _ -> false)

testPlacementChoiceBuildsSubmission :: Effect Unit
testPlacementChoiceBuildsSubmission = do
  let
    loading = update StartPlacementTest authedDashboard.state
    loaded = update (PlacementQuestionsLoaded LiveBackend placementQuestions) loading.state
    picked = update (ChoosePlacementChoice 1) loaded.state
    continued = update ContinuePlacement picked.state
  assert (case picked.state.placementSession of
    PlacementActive session ->
      case buildPlacementAnswer session of
        Just answer -> answer.questionId == "placement-c2-stance" && answer.selectedChoice == Just "The wording is ostensibly neutral, but it implies skepticism."
        Nothing -> false
    _ -> false)
  assert (case Array.head continued.commands of
    Just (SendPlacement submission) ->
      case Array.head submission.answers of
        Just answer -> answer.questionId == "placement-c2-stance" && answer.selectedChoice == Just "The wording is ostensibly neutral, but it implies skepticism."
        Nothing -> false
    _ -> false)

testPlacementResultPatchesBootstrap :: Effect Unit
testPlacementResultPatchesBootstrap = do
  let
    loading = update StartPlacementTest authedDashboard.state
    loaded = update (PlacementQuestionsLoaded LiveBackend placementQuestions) loading.state
    picked = update (ChoosePlacementChoice 1) loaded.state
    submitted = update ContinuePlacement picked.state
    completed = update (PlacementLoaded LiveBackend placementResult) submitted.state
  assert (case completed.state.bootstrap of
    Loaded bootstrap -> bootstrap.profile.xp == placementResult.bootstrap.profile.xp && bootstrap.recommendedLessonId == Just "lesson-weekend-plans"
    _ -> false)
  assert (completed.state.selectedUnitId == Just "unit-next-steps")
  assert (case completed.state.placementSession of
    PlacementActive session -> session.result /= Nothing && session.submitting == false
    _ -> false)

signedOutSession :: SessionSnapshot
signedOutSession =
  { viewer: Nothing
  , authConfig:
      { googleEnabled: true
      , googleClientId: Just "test-client-id"
      , devLoginEnabled: true
      , devLoginOptions:
          [ { email: "alex@dev.local", displayName: "Alex Dev" }
          ]
      }
  }

signedInSession :: SessionSnapshot
signedInSession =
  signedOutSession
    { viewer =
        Just
          { displayName: "Learner"
          , email: "learner@example.com"
          , avatarUrl: Nothing
          , provider: Google
          }
    }

authedDashboard :: { state :: AppState, commands :: Array Command }
authedDashboard =
  let
    authed = update (SessionSnapshotLoaded signedInSession) initialState
  in
    update (BootstrapLoaded LiveBackend initialBootstrap) authed.state

fromMaybePrompt :: VocabularyReviewPrompt
fromMaybePrompt =
  fromMaybe
    { reviewId: "lex-routine:Recognition"
    , lexemeId: "lex-routine"
    , dimension: Recognition
    , prompt: "Which word matches this meaning?"
    , promptDetail: Just "A usual set of actions you do regularly."
    , choices: [ "ticket", "routine", "medicine" ]
    , answerText: Nothing
    , acceptableAnswers: [ "routine" ]
    , hint: Nothing
    , explanation: "Recognition checks whether the meaning activates the right word."
    , masteryPercent: 30
    , dueLabel: "New word"
    }
    (Array.head initialBootstrap.vocabulary.reviewQueue)

placementQuestions :: Array PlacementQuestion
placementQuestions =
  [ { questionId: "placement-c2-stance"
    , cefrBand: "C2"
    , skill: "implied stance"
    , prompt: "Choose the sentence with subtle stance and implication."
    , promptDetail: Nothing
    , choices:
        [ "The wording is certainly neutral."
        , "The wording is ostensibly neutral, but it implies skepticism."
        , "The wording is words."
        ]
    }
  ]

placementResult :: PlacementResult
placementResult =
  { placedCefrBand: "C2"
  , scorePercent: 100
  , xpAwarded: 2400
  , completedLessonsDelta: 2
  , recommendedLessonId: Just "lesson-weekend-plans"
  , bootstrap:
      initialBootstrap
        { profile = initialBootstrap.profile { xp = initialBootstrap.profile.xp + 2400, completedLessons = 3 }
        , recommendedLessonId = Just "lesson-weekend-plans"
        }
  }

singleChoiceAttempt :: AttemptView
singleChoiceAttempt =
  { attemptId: "attempt-1"
  , lesson:
      { lessonId: "lesson-1"
      , unitId: "unit-1"
      , index: 1
      , title: "Choice Test"
      , subtitle: "single prompt"
      , goal: "Choose one answer."
      , xpReward: 20
      , exerciseCount: 1
      , status: Available
      , masteryPercent: 0
      }
  , narrative: "Narrative"
  , tips: []
  , exercises:
      [ { exerciseId: "exercise-1"
        , lessonId: "lesson-1"
        , kind: MultipleChoice
        , prompt: "Choose the correct sentence."
        , promptDetail: Nothing
        , choices: [ "A", "B" ]
        , fragments: []
        , answerText: Just "B"
        , acceptableAnswers: [ "B" ]
        , translation: Nothing
        , hint: Nothing
        , explanation: "B is correct."
        }
      ]
  , currentIndex: 0
  }

clozeAttempt :: AttemptView
clozeAttempt =
  { attemptId: "attempt-cloze"
  , lesson: testLesson "lesson-cloze" "Cloze Test" Cloze
  , narrative: "Narrative"
  , tips: []
  , exercises:
      [ { exerciseId: "exercise-cloze"
        , lessonId: "lesson-cloze"
        , kind: Cloze
        , prompt: "Fill in the missing verb."
        , promptDetail: Just "We ____ classmates."
        , choices: []
        , fragments: []
        , answerText: Just "are"
        , acceptableAnswers: [ "are" ]
        , translation: Nothing
        , hint: Nothing
        , explanation: "We takes are."
        }
      ]
  , currentIndex: 0
  }

orderingAttempt :: AttemptView
orderingAttempt =
  { attemptId: "attempt-ordering"
  , lesson: testLesson "lesson-ordering" "Ordering Test" Ordering
  , narrative: "Narrative"
  , tips: []
  , exercises:
      [ { exerciseId: "exercise-ordering"
        , lessonId: "lesson-ordering"
        , kind: Ordering
        , prompt: "Build the sentence."
        , promptDetail: Nothing
        , choices: []
        , fragments: [ "from", "I", "Osaka", "am" ]
        , answerText: Nothing
        , acceptableAnswers: [ "I am from Osaka" ]
        , translation: Nothing
        , hint: Nothing
        , explanation: "Subject plus verb."
        }
      ]
  , currentIndex: 0
  }

trueFalseAttempt :: AttemptView
trueFalseAttempt =
  { attemptId: "attempt-boolean"
  , lesson: testLesson "lesson-boolean" "True False Test" TrueFalse
  , narrative: "Narrative"
  , tips: []
  , exercises:
      [ { exerciseId: "exercise-boolean"
        , lessonId: "lesson-boolean"
        , kind: TrueFalse
        , prompt: "Decide if the sentence is correct."
        , promptDetail: Just "She go to work."
        , choices: [ "true", "false" ]
        , fragments: []
        , answerText: Nothing
        , acceptableAnswers: [ "false" ]
        , translation: Nothing
        , hint: Nothing
        , explanation: "Use goes."
        }
      ]
  , currentIndex: 0
  }

testLesson :: String -> String -> ExerciseKind -> LessonSummary
testLesson lessonId title _ =
  { lessonId
  , unitId: "unit-1"
  , index: 1
  , title
  , subtitle: "single prompt"
  , goal: "Submit one answer."
  , xpReward: 20
  , exerciseCount: 1
  , status: Available
  , masteryPercent: 0
  }
