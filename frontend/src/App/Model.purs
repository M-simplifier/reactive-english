module App.Model
  ( ActiveSession
  , AppState
  , AuthFlow
  , AuthState(..)
  , Command(..)
  , CompletionBanner
  , DataSource(..)
  , DraftAnswer(..)
  , LoadState(..)
  , Msg(..)
  , PreviewState(..)
  , SessionState(..)
  , ActiveVocabularySession
  , VocabularyDraft(..)
  , VocabularyState(..)
  , activeExercise
  , activeProgressPercent
  , buildSubmission
  , buildVocabularySubmission
  , cacheLessonDetail
  , currentViewer
  , defaultSelectedUnitId
  , emptyDraftFor
  , emptyVocabularyDraftFor
  , findLessonSummary
  , findUnitSummary
  , googleClientIdForSignIn
  , initialState
  , isAuthenticated
  , lessonIsStartable
  , selectedUnitSummary
  , update
  , vocabularyActivePrompt
  ) where

import Prelude (class Eq, class Functor, bind, div, map, max, not, otherwise, pure, (&&), (*), (+), (/=), (<<<), (<=), (<>), (==), (>>=), (||))

import App.Schema.Generated
  ( AnswerFeedback
  , AnswerSubmission
  , AppBootstrap
  , AttemptCompletion
  , AttemptProgress
  , AttemptView
  , ExerciseKind(..)
  , ExercisePrompt
  , LessonDetail
  , LessonStatus(..)
  , LessonSummary
  , SessionSnapshot
  , UnitSummary
  , UserSummary
  , VocabularyFeedback
  , VocabularyReviewPrompt
  , VocabularyReviewResult
  , VocabularyReviewSubmission
  )
import Control.Alt ((<|>))
import Data.Array as Array
import Data.Maybe (Maybe(..), isJust, maybe)
import Data.String.Common (trim)

data DataSource
  = LiveBackend
  | DemoFallback

derive instance eqDataSource :: Eq DataSource

data LoadState a
  = NotAsked
  | Loading
  | Loaded a
  | Failed String

derive instance functorLoadState :: Functor LoadState

data AuthState
  = AuthLoading
  | AuthReady AuthFlow
  | AuthFailed String

type AuthFlow =
  { snapshot :: SessionSnapshot
  , busy :: Boolean
  , message :: Maybe String
  }

data PreviewState
  = PreviewClosed
  | PreviewLoading String
  | PreviewReady LessonDetail
  | PreviewFailed String String

data DraftAnswer
  = NoDraft
  | ChoiceDraft Int
  | BooleanDraft Boolean
  | OrderingDraft (Array Int)
  | TextDraft String

data SessionState
  = SessionClosed
  | SessionOpening String
  | SessionActive ActiveSession
  | SessionFailed String

type ActiveSession =
  { attempt :: AttemptView
  , currentIndex :: Int
  , answeredCount :: Int
  , correctCount :: Int
  , draft :: DraftAnswer
  , feedback :: Maybe AnswerFeedback
  , message :: Maybe String
  , submitting :: Boolean
  , finished :: Boolean
  }

data VocabularyDraft
  = VocabularyNoDraft
  | VocabularyChoiceDraft Int
  | VocabularyTextDraft String

data VocabularyState
  = VocabularyClosed
  | VocabularyLoading
  | VocabularyActive ActiveVocabularySession
  | VocabularyFailed String

type ActiveVocabularySession =
  { prompts :: Array VocabularyReviewPrompt
  , currentIndex :: Int
  , draft :: VocabularyDraft
  , feedback :: Maybe VocabularyFeedback
  , message :: Maybe String
  , submitting :: Boolean
  }

type CompletionBanner =
  { title :: String
  , detail :: String
  , xpAwarded :: Int
  , unlockedLessonId :: Maybe String
  }

type AppState =
  { auth :: AuthState
  , bootstrap :: LoadState AppBootstrap
  , selectedUnitId :: Maybe String
  , preview :: PreviewState
  , lessonCache :: Array LessonDetail
  , session :: SessionState
  , vocabularySession :: VocabularyState
  , banner :: Maybe CompletionBanner
  , dataSource :: DataSource
  }

data Msg
  = AppStarted
  | SessionSnapshotLoaded SessionSnapshot
  | SessionSnapshotFailed String
  | GoogleCredentialReceived String
  | GoogleCredentialFailed String
  | RequestDevLogin String
  | RequestLogout
  | AuthActionCompleted SessionSnapshot
  | AuthActionFailed String
  | BootstrapLoaded DataSource AppBootstrap
  | BootstrapFailed String
  | SelectUnit String
  | PreviewLesson String
  | ClosePreview
  | LessonPreviewLoaded DataSource LessonDetail
  | LessonPreviewFailed String
  | StartLesson String
  | AttemptLoaded DataSource AttemptView
  | AttemptFailed String
  | ChooseChoice Int
  | ChooseBoolean Boolean
  | OrderingPick Int
  | OrderingUnpick Int
  | SubmitTextAnswer String
  | CheckAnswer
  | AnswerProgressLoaded DataSource AttemptProgress
  | AnswerProgressFailed String
  | AdvanceAfterFeedback
  | CompletionLoaded DataSource AttemptCompletion
  | CompletionFailed String
  | StartVocabularyReview
  | VocabularyReviewPromptsLoaded DataSource (Array VocabularyReviewPrompt)
  | VocabularyReviewPromptsFailed String
  | ChooseVocabularyChoice Int
  | SubmitVocabularyTextAnswer String
  | CheckVocabularyAnswer
  | VocabularyReviewLoaded DataSource VocabularyReviewResult
  | VocabularyReviewFailed String
  | AdvanceVocabularyReview
  | CloseVocabularyReview
  | ReturnDashboard
  | DismissBanner

data Command
  = LoadSessionSnapshot
  | ExchangeGoogleCredential String
  | RunDevLogin String
  | Logout
  | LoadBootstrap
  | LoadLessonPreview String
  | OpenAttempt String
  | SendAnswer String AnswerSubmission
  | FinishAttempt String String
  | LoadVocabularyReviewPrompts
  | SendVocabularyReview VocabularyReviewSubmission

type Transition =
  { state :: AppState
  , commands :: Array Command
  }

initialState :: AppState
initialState =
  { auth: AuthLoading
  , bootstrap: NotAsked
  , selectedUnitId: Nothing
  , preview: PreviewClosed
  , lessonCache: []
  , session: SessionClosed
  , vocabularySession: VocabularyClosed
  , banner: Nothing
  , dataSource: LiveBackend
  }

update :: Msg -> AppState -> Transition
update msg state =
  case msg of
    AppStarted ->
      transition
        ( resetForAuthChange state
            { auth = AuthLoading
            , bootstrap = NotAsked
            , banner = Nothing
            }
        )
        [ LoadSessionSnapshot ]

    SessionSnapshotLoaded snapshot ->
      applySnapshot snapshot state

    SessionSnapshotFailed message ->
      case state.auth of
        AuthReady flow ->
          transition
            ( state
                { auth = AuthReady (flow { busy = false, message = Just message })
                , bootstrap = NotAsked
                }
            )
            []

        _ ->
          transition
            ( resetForAuthChange state
                { auth = AuthFailed message
                , bootstrap = Failed message
                }
            )
            []

    GoogleCredentialReceived credential ->
      case state.auth of
        AuthReady flow ->
          transition
            ( state
                { auth =
                    AuthReady
                      ( flow
                          { busy = true
                          , message = Just "Signing in with Google..."
                          }
                      )
                }
            )
            [ ExchangeGoogleCredential credential ]

        _ ->
          transition state []

    GoogleCredentialFailed message ->
      update (AuthActionFailed message) state

    RequestDevLogin email ->
      case state.auth of
        AuthReady flow ->
          transition
            ( state
                { auth =
                    AuthReady
                      ( flow
                          { busy = true
                          , message = Just ("Signing in as " <> email <> "...")
                          }
                      )
                }
            )
            [ RunDevLogin email ]

        _ ->
          transition state []

    RequestLogout ->
      case state.auth of
        AuthReady flow | isJust flow.snapshot.viewer ->
          transition
            ( state
                { auth =
                    AuthReady
                      ( flow
                          { busy = true
                          , message = Just "Signing out..."
                          }
                      )
                }
            )
            [ Logout ]

        _ ->
          transition state []

    AuthActionCompleted snapshot ->
      applySnapshot snapshot state

    AuthActionFailed message ->
      case state.auth of
        AuthReady flow ->
          transition
            (state { auth = AuthReady (flow { busy = false, message = Just message }) })
            []

        _ ->
          transition state []

    BootstrapLoaded source bootstrap ->
      transition
        ( state
            { bootstrap = Loaded bootstrap
            , selectedUnitId = state.selectedUnitId <|> defaultSelectedUnitId bootstrap
            , dataSource = source
            }
        )
        []

    BootstrapFailed message ->
      transition (state { bootstrap = Failed message }) []

    SelectUnit unitId ->
      transition (state { selectedUnitId = Just unitId }) []

    PreviewLesson lessonId ->
      case Array.find (\detail -> detail.lesson.lessonId == lessonId) state.lessonCache of
        Just detail ->
          transition
            ( state
                { preview = PreviewReady detail
                , selectedUnitId = Just detail.lesson.unitId
                }
            )
            []

        Nothing ->
          transition
            (state { preview = PreviewLoading lessonId })
            [ LoadLessonPreview lessonId ]

    ClosePreview ->
      transition (state { preview = PreviewClosed }) []

    LessonPreviewLoaded source detail ->
      transition
        ( state
            { preview = PreviewReady detail
            , lessonCache = cacheLessonDetail detail state.lessonCache
            , selectedUnitId = Just detail.lesson.unitId
            , dataSource = source
            }
        )
        []

    LessonPreviewFailed message ->
      let
        lessonId = case state.preview of
          PreviewLoading current -> current
          _ -> ""
      in
        transition (state { preview = PreviewFailed lessonId message }) []

    StartLesson lessonId ->
      transition
        ( state
            { preview = PreviewClosed
            , session = SessionOpening lessonId
            , banner = Nothing
            }
        )
        [ OpenAttempt lessonId ]

    AttemptLoaded source attempt ->
      let
        firstDraft = maybe NoDraft emptyDraftFor (Array.index attempt.exercises attempt.currentIndex)
      in
        transition
          ( state
              { session =
                  SessionActive
                    { attempt
                    , currentIndex: attempt.currentIndex
                    , answeredCount: attempt.currentIndex
                    , correctCount: 0
                    , draft: firstDraft
                    , feedback: Nothing
                    , message: Nothing
                    , submitting: false
                    , finished: false
                    }
              , dataSource = source
              }
          )
          []

    AttemptFailed message ->
      transition (state { session = SessionFailed message }) []

    ChooseChoice choiceIndex ->
      transition (overActiveSession (\session -> session { draft = ChoiceDraft choiceIndex, message = Nothing }) state) []

    ChooseBoolean answer ->
      transition (overActiveSession (\session -> session { draft = BooleanDraft answer, message = Nothing }) state) []

    OrderingPick fragmentIndex ->
      transition
        ( overActiveSession
            (\session ->
              case session.draft of
                OrderingDraft chosen ->
                  if Array.elem fragmentIndex chosen then
                    session
                  else
                    session { draft = OrderingDraft (chosen <> [ fragmentIndex ]), message = Nothing }

                _ ->
                  session { draft = OrderingDraft [ fragmentIndex ], message = Nothing }
            )
            state
        )
        []

    OrderingUnpick fragmentIndex ->
      transition
        ( overActiveSession
            (\session ->
              case session.draft of
                OrderingDraft chosen ->
                  session
                    { draft = OrderingDraft (Array.filter (_ /= fragmentIndex) chosen)
                    , message = Nothing
                    }

                _ ->
                  session
            )
            state
        )
        []

    SubmitTextAnswer answerText ->
      submitCurrentAnswer (overActiveSession (\session -> session { draft = TextDraft answerText, message = Nothing }) state)

    CheckAnswer ->
      case state.vocabularySession of
        VocabularyActive _ ->
          submitCurrentVocabularyAnswer state

        _ ->
          submitCurrentAnswer state

    AnswerProgressLoaded source progress ->
      let
        updatedState =
          overActiveSession
            (\session ->
              case progress.lastFeedback of
                Just feedback ->
                  session
                    { feedback = Just feedback
                    , answeredCount = progress.answeredCount
                    , correctCount = progress.correctCount
                    , message = Nothing
                    , submitting = false
                    , finished = progress.finished
                    }

                Nothing ->
                  session
                    { submitting = false
                    , message = Just "The server returned progress without feedback."
                    }
            )
            state
      in
        transition (updatedState { dataSource = source }) []

    AnswerProgressFailed message ->
      transition
        (overActiveSession (\session -> session { submitting = false, message = Just message }) state)
        []

    AdvanceAfterFeedback ->
      advanceAfterFeedback state

    CompletionLoaded source completion ->
      let
        nextBootstrap = case state.bootstrap of
          Loaded bootstrap -> Loaded (applyCompletion completion bootstrap)
          current -> current
      in
        transition
          ( state
              { bootstrap = nextBootstrap
              , session = SessionClosed
              , preview = PreviewClosed
              , banner =
                  Just
                    { title: if completion.lessonCompleted then "Lesson complete" else "Session wrapped"
                    , detail: completionMessage completion
                    , xpAwarded: completion.xpAwarded
                    , unlockedLessonId: completion.newlyUnlockedLessonId
                    }
              , dataSource = source
              }
          )
          []

    CompletionFailed message ->
      transition
        (overActiveSession (\session -> session { submitting = false, message = Just message }) state)
        []

    StartVocabularyReview ->
      case state.bootstrap of
        Loaded bootstrap ->
          if Array.null bootstrap.vocabulary.reviewQueue then
            transition (state { vocabularySession = VocabularyLoading }) [ LoadVocabularyReviewPrompts ]
          else
            transition (state { vocabularySession = openVocabularySession bootstrap.vocabulary.reviewQueue }) []

        _ ->
          transition (state { vocabularySession = VocabularyFailed "Load the dashboard before starting word review." }) []

    VocabularyReviewPromptsLoaded source prompts ->
      if Array.null prompts then
        transition
          ( state
              { vocabularySession = VocabularyFailed "No word cards are due right now."
              , dataSource = source
              }
          )
          []
      else
        transition
          ( state
              { vocabularySession = openVocabularySession prompts
              , dataSource = source
              }
          )
          []

    VocabularyReviewPromptsFailed message ->
      transition (state { vocabularySession = VocabularyFailed message }) []

    ChooseVocabularyChoice choiceIndex ->
      transition
        (overActiveVocabularySession (\session -> session { draft = VocabularyChoiceDraft choiceIndex, message = Nothing }) state)
        []

    SubmitVocabularyTextAnswer answer ->
      submitCurrentVocabularyAnswer (overActiveVocabularySession (\session -> session { draft = VocabularyTextDraft answer, message = Nothing }) state)

    CheckVocabularyAnswer ->
      case state.vocabularySession of
        VocabularyActive _ ->
          submitCurrentVocabularyAnswer state

        _ ->
          submitCurrentAnswer state

    VocabularyReviewLoaded source result ->
      let
        updatedBootstrap = case state.bootstrap of
          Loaded bootstrap ->
            Loaded (bootstrap { profile = result.profile, vocabulary = result.dashboard })
          current ->
            current
        updatedState =
          overActiveVocabularySession
            ( \session ->
                session
                  { feedback = Just result.feedback
                  , message = Nothing
                  , submitting = false
                  }
            )
            state
      in
        transition
          ( updatedState
              { bootstrap = updatedBootstrap
              , dataSource = source
              }
          )
          []

    VocabularyReviewFailed message ->
      transition
        (overActiveVocabularySession (\session -> session { submitting = false, message = Just message }) state)
        []

    AdvanceVocabularyReview ->
      advanceVocabularyReview state

    CloseVocabularyReview ->
      transition (state { vocabularySession = VocabularyClosed }) []

    ReturnDashboard ->
      transition
        (state { session = SessionClosed, vocabularySession = VocabularyClosed, preview = PreviewClosed })
        []

    DismissBanner ->
      transition (state { banner = Nothing }) []

transition :: AppState -> Array Command -> Transition
transition nextState commands =
  { state: nextState, commands }

applySnapshot :: SessionSnapshot -> AppState -> Transition
applySnapshot snapshot state =
  let
    resetState = resetForAuthChange state
  in
    if isJust snapshot.viewer then
      transition
        ( resetState
            { auth = AuthReady { snapshot, busy: false, message: Nothing }
            , bootstrap = Loading
            }
        )
        [ LoadBootstrap ]
    else
      transition
        ( resetState
            { auth = AuthReady { snapshot, busy: false, message: Nothing }
            , bootstrap = NotAsked
            }
        )
        []

resetForAuthChange :: AppState -> AppState
resetForAuthChange state =
  state
    { bootstrap = NotAsked
    , selectedUnitId = Nothing
    , preview = PreviewClosed
    , lessonCache = []
    , session = SessionClosed
    , vocabularySession = VocabularyClosed
    , banner = Nothing
    }

submitCurrentAnswer :: AppState -> Transition
submitCurrentAnswer state =
  case state.session of
    SessionActive session ->
      case buildSubmission session of
        Just submission ->
          transition
            ( state
                { session =
                    SessionActive
                      ( session
                          { submitting = true
                          , message = Nothing
                          }
                      )
                }
            )
            [ SendAnswer session.attempt.attemptId submission ]

        Nothing ->
          transition
            ( overActiveSession
                (\session' ->
                  session'
                    { message = Just "Choose or type an answer before checking."
                    }
                )
                state
            )
            []

    _ ->
      transition state []

advanceAfterFeedback :: AppState -> Transition
advanceAfterFeedback state =
  case state.session of
    SessionActive session ->
      if isJust session.feedback then
        if session.finished then
          transition
            ( overActiveSession
                (\current ->
                  current
                    { submitting = true
                    , message = Just "Wrapping up your lesson..."
                    }
                )
                state
            )
            [ FinishAttempt session.attempt.attemptId session.attempt.lesson.lessonId ]
        else
          let
            nextIndex = session.answeredCount
            nextDraft = maybe NoDraft emptyDraftFor (Array.index session.attempt.exercises nextIndex)
          in
            transition
              ( state
                  { session =
                      SessionActive
                        ( session
                            { currentIndex = nextIndex
                            , draft = nextDraft
                            , feedback = Nothing
                            , message = Nothing
                            , submitting = false
                            }
                        )
                  }
              )
              []
      else
        transition state []

    _ ->
      transition state []

openVocabularySession :: Array VocabularyReviewPrompt -> VocabularyState
openVocabularySession prompts =
  case Array.head prompts of
    Just prompt ->
      VocabularyActive
        { prompts
        , currentIndex: 0
        , draft: emptyVocabularyDraftFor prompt
        , feedback: Nothing
        , message: Nothing
        , submitting: false
        }

    Nothing ->
      VocabularyFailed "No word cards are due right now."

submitCurrentVocabularyAnswer :: AppState -> Transition
submitCurrentVocabularyAnswer state =
  case state.vocabularySession of
    VocabularyActive session ->
      case buildVocabularySubmission session of
        Just submission ->
          transition
            ( state
                { vocabularySession =
                    VocabularyActive
                      ( session
                          { submitting = true
                          , message = Nothing
                          }
                      )
                }
            )
            [ SendVocabularyReview submission ]

        Nothing ->
          transition
            ( overActiveVocabularySession
                (\session' -> session' { message = Just "Choose or type an answer before checking." })
                state
            )
            []

    _ ->
      transition state []

advanceVocabularyReview :: AppState -> Transition
advanceVocabularyReview state =
  case state.vocabularySession of
    VocabularyActive session ->
      if isJust session.feedback then
        let
          nextIndex = session.currentIndex + 1
        in
          case Array.index session.prompts nextIndex of
            Just prompt ->
              transition
                ( state
                    { vocabularySession =
                        VocabularyActive
                          ( session
                              { currentIndex = nextIndex
                              , draft = emptyVocabularyDraftFor prompt
                              , feedback = Nothing
                              , message = Nothing
                              , submitting = false
                              }
                          )
                    }
                )
                []

            Nothing ->
              transition (state { vocabularySession = VocabularyClosed }) []
      else
        transition state []

    _ ->
      transition state []

overActiveSession :: (ActiveSession -> ActiveSession) -> AppState -> AppState
overActiveSession f state =
  case state.session of
    SessionActive session -> state { session = SessionActive (f session) }
    _ -> state

overActiveVocabularySession :: (ActiveVocabularySession -> ActiveVocabularySession) -> AppState -> AppState
overActiveVocabularySession f state =
  case state.vocabularySession of
    VocabularyActive session -> state { vocabularySession = VocabularyActive (f session) }
    _ -> state

activeExercise :: ActiveSession -> Maybe ExercisePrompt
activeExercise session =
  Array.index session.attempt.exercises session.currentIndex

activeProgressPercent :: ActiveSession -> Int
activeProgressPercent session =
  let
    total = Array.length session.attempt.exercises
  in
    if total <= 0 then
      0
    else
      div (session.answeredCount * 100) total

buildSubmission :: ActiveSession -> Maybe AnswerSubmission
buildSubmission session =
  do
    exercise <- activeExercise session
    case exercise.kind of
      MultipleChoice ->
        case session.draft of
          ChoiceDraft choiceIndex -> do
            choice <- Array.index exercise.choices choiceIndex
            pure
              { exerciseId: exercise.exerciseId
              , answerText: Nothing
              , selectedChoices: [ choice ]
              , booleanAnswer: Nothing
              }

          _ ->
            Nothing

      Cloze ->
        case session.draft of
          TextDraft answer ->
            let
              cleaned = trim answer
            in
              if cleaned == "" then
                Nothing
              else
                pure
                  { exerciseId: exercise.exerciseId
                  , answerText: Just cleaned
                  , selectedChoices: []
                  , booleanAnswer: Nothing
                  }

          _ ->
            Nothing

      Ordering ->
        case session.draft of
          OrderingDraft fragmentIndexes ->
            let
              chosen =
                Array.mapMaybe (\index -> Array.index exercise.fragments index) fragmentIndexes
            in
              if Array.null chosen then
                Nothing
              else
                pure
                  { exerciseId: exercise.exerciseId
                  , answerText: Nothing
                  , selectedChoices: chosen
                  , booleanAnswer: Nothing
                  }

          _ ->
            Nothing

      TrueFalse ->
        case session.draft of
          BooleanDraft answer ->
            pure
              { exerciseId: exercise.exerciseId
              , answerText: Nothing
              , selectedChoices: []
              , booleanAnswer: Just answer
              }

          _ ->
            Nothing

vocabularyActivePrompt :: ActiveVocabularySession -> Maybe VocabularyReviewPrompt
vocabularyActivePrompt session =
  Array.index session.prompts session.currentIndex

buildVocabularySubmission :: ActiveVocabularySession -> Maybe VocabularyReviewSubmission
buildVocabularySubmission session =
  do
    prompt <- vocabularyActivePrompt session
    case session.draft of
      VocabularyChoiceDraft choiceIndex ->
        if Array.null prompt.choices then
          Nothing
        else do
          choice <- Array.index prompt.choices choiceIndex
          pure
            { reviewId: prompt.reviewId
            , lexemeId: prompt.lexemeId
            , dimension: prompt.dimension
            , answerText: Nothing
            , selectedChoice: Just choice
            }

      VocabularyTextDraft answer ->
        let
          cleaned = trim answer
        in
          if cleaned == "" then
            Nothing
          else
            pure
              { reviewId: prompt.reviewId
              , lexemeId: prompt.lexemeId
              , dimension: prompt.dimension
              , answerText: Just cleaned
              , selectedChoice: Nothing
              }

      _ ->
        Nothing

emptyVocabularyDraftFor :: VocabularyReviewPrompt -> VocabularyDraft
emptyVocabularyDraftFor prompt =
  if Array.null prompt.choices then
    VocabularyTextDraft ""
  else
    VocabularyNoDraft

emptyDraftFor :: ExercisePrompt -> DraftAnswer
emptyDraftFor exercise =
  case exercise.kind of
    MultipleChoice -> NoDraft
    Cloze -> TextDraft ""
    Ordering -> OrderingDraft []
    TrueFalse -> NoDraft

cacheLessonDetail :: LessonDetail -> Array LessonDetail -> Array LessonDetail
cacheLessonDetail detail cache =
  if Array.any (\existing -> existing.lesson.lessonId == detail.lesson.lessonId) cache then
    map (\existing -> if existing.lesson.lessonId == detail.lesson.lessonId then detail else existing) cache
  else
    cache <> [ detail ]

defaultSelectedUnitId :: AppBootstrap -> Maybe String
defaultSelectedUnitId bootstrap =
  case Array.find _.unlocked bootstrap.units of
    Just unit -> Just unit.unitId
    Nothing -> map _.unitId (Array.head bootstrap.units)

findUnitSummary :: AppBootstrap -> String -> Maybe UnitSummary
findUnitSummary bootstrap unitId =
  Array.find (\unit -> unit.unitId == unitId) bootstrap.units

selectedUnitSummary :: AppState -> Maybe UnitSummary
selectedUnitSummary state =
  case state.bootstrap, state.selectedUnitId of
    Loaded bootstrap, Just unitId -> findUnitSummary bootstrap unitId
    Loaded bootstrap, Nothing ->
      defaultSelectedUnitId bootstrap >>= findUnitSummary bootstrap
    _, _ -> Nothing

findLessonSummary :: AppBootstrap -> String -> Maybe LessonSummary
findLessonSummary bootstrap lessonId =
  Array.find (\lesson -> lesson.lessonId == lessonId)
    (Array.concatMap _.lessonSummaries bootstrap.units)

lessonIsStartable :: LessonSummary -> Boolean
lessonIsStartable lesson =
  lesson.status /= Locked

completionMessage :: AttemptCompletion -> String
completionMessage completion =
  case completion.newlyUnlockedLessonId of
    Just _ ->
      "You banked fresh XP and opened the next stop on the path."
    Nothing ->
      "Progress saved. Your dashboard stats are refreshed."

applyCompletion :: AttemptCompletion -> AppBootstrap -> AppBootstrap
applyCompletion completion bootstrap =
  let
    updatedUnits = map (patchUnit completion) bootstrap.units
    recommended =
      case completion.newlyUnlockedLessonId of
        Just lessonId -> Just lessonId
        Nothing -> bootstrap.recommendedLessonId
  in
    bootstrap
      { profile = completion.profile
      , stats = completion.stats
      , recommendedLessonId = recommended
      , units = updatedUnits
      }

patchUnit :: AttemptCompletion -> UnitSummary -> UnitSummary
patchUnit completion unit =
  let
    patchedLessons = map patchLesson unit.lessonSummaries
    completedCount =
      Array.length (Array.filter (\lesson -> lesson.status == Completed) patchedLessons)
    unlocked =
      unit.unlocked || Array.any lessonIsStartable patchedLessons
  in
    unit
      { lessonSummaries = patchedLessons
      , completedLessons = completedCount
      , unlocked = unlocked
      }
  where
  patchLesson lesson
    | lesson.lessonId == completion.lessonId =
        lesson { status = Completed, masteryPercent = max lesson.masteryPercent 100 }
    | Just lesson.lessonId == completion.newlyUnlockedLessonId && lesson.status == Locked =
        lesson { status = Available }
    | otherwise =
        lesson

currentViewer :: AppState -> Maybe UserSummary
currentViewer state =
  case state.auth of
    AuthReady flow -> flow.snapshot.viewer
    _ -> Nothing

isAuthenticated :: AppState -> Boolean
isAuthenticated = isJust <<< currentViewer

googleClientIdForSignIn :: AppState -> Maybe String
googleClientIdForSignIn state =
  case state.auth of
    AuthReady flow | isNothing flow.snapshot.viewer && flow.snapshot.authConfig.googleEnabled ->
      flow.snapshot.authConfig.googleClientId
    _ ->
      Nothing
  where
  isNothing = not <<< isJust
