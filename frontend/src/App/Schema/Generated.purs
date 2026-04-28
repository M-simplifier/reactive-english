module App.Schema.Generated where

import Prelude

import Data.Argonaut.Decode (class DecodeJson, decodeJson)
import Data.Argonaut.Decode.Error (JsonDecodeError(..))
import Data.Argonaut.Encode (class EncodeJson, encodeJson)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))

data LessonStatus = Locked | Available | InProgress | Completed

derive instance eqLessonStatus :: Eq LessonStatus
derive instance ordLessonStatus :: Ord LessonStatus

lessonStatusFromString :: String -> Maybe LessonStatus
lessonStatusFromString value = case value of
  "Locked" -> Just Locked
  "Available" -> Just Available
  "InProgress" -> Just InProgress
  "Completed" -> Just Completed
  _ -> Nothing

lessonStatusToString :: LessonStatus -> String
lessonStatusToString value = case value of
  Locked -> "Locked"
  Available -> "Available"
  InProgress -> "InProgress"
  Completed -> "Completed"

instance decodeJsonLessonStatus :: DecodeJson LessonStatus where
  decodeJson json = do
    value <- decodeJson json
    case lessonStatusFromString value of
      Just enumValue -> pure enumValue
      Nothing -> Left (TypeMismatch "LessonStatus")

instance encodeJsonLessonStatus :: EncodeJson LessonStatus where
  encodeJson = encodeJson <<< lessonStatusToString

data AuthProvider = Google | Dev

derive instance eqAuthProvider :: Eq AuthProvider
derive instance ordAuthProvider :: Ord AuthProvider

authProviderFromString :: String -> Maybe AuthProvider
authProviderFromString value = case value of
  "Google" -> Just Google
  "Dev" -> Just Dev
  _ -> Nothing

authProviderToString :: AuthProvider -> String
authProviderToString value = case value of
  Google -> "Google"
  Dev -> "Dev"

instance decodeJsonAuthProvider :: DecodeJson AuthProvider where
  decodeJson json = do
    value <- decodeJson json
    case authProviderFromString value of
      Just enumValue -> pure enumValue
      Nothing -> Left (TypeMismatch "AuthProvider")

instance encodeJsonAuthProvider :: EncodeJson AuthProvider where
  encodeJson = encodeJson <<< authProviderToString

data ExerciseKind = MultipleChoice | Cloze | Ordering | TrueFalse

derive instance eqExerciseKind :: Eq ExerciseKind
derive instance ordExerciseKind :: Ord ExerciseKind

exerciseKindFromString :: String -> Maybe ExerciseKind
exerciseKindFromString value = case value of
  "MultipleChoice" -> Just MultipleChoice
  "Cloze" -> Just Cloze
  "Ordering" -> Just Ordering
  "TrueFalse" -> Just TrueFalse
  _ -> Nothing

exerciseKindToString :: ExerciseKind -> String
exerciseKindToString value = case value of
  MultipleChoice -> "MultipleChoice"
  Cloze -> "Cloze"
  Ordering -> "Ordering"
  TrueFalse -> "TrueFalse"

instance decodeJsonExerciseKind :: DecodeJson ExerciseKind where
  decodeJson json = do
    value <- decodeJson json
    case exerciseKindFromString value of
      Just enumValue -> pure enumValue
      Nothing -> Left (TypeMismatch "ExerciseKind")

instance encodeJsonExerciseKind :: EncodeJson ExerciseKind where
  encodeJson = encodeJson <<< exerciseKindToString

data KnowledgeDimension = Recognition | MeaningRecall | FormRecall | UseInContext | Collocation

derive instance eqKnowledgeDimension :: Eq KnowledgeDimension
derive instance ordKnowledgeDimension :: Ord KnowledgeDimension

knowledgeDimensionFromString :: String -> Maybe KnowledgeDimension
knowledgeDimensionFromString value = case value of
  "Recognition" -> Just Recognition
  "MeaningRecall" -> Just MeaningRecall
  "FormRecall" -> Just FormRecall
  "UseInContext" -> Just UseInContext
  "Collocation" -> Just Collocation
  _ -> Nothing

knowledgeDimensionToString :: KnowledgeDimension -> String
knowledgeDimensionToString value = case value of
  Recognition -> "Recognition"
  MeaningRecall -> "MeaningRecall"
  FormRecall -> "FormRecall"
  UseInContext -> "UseInContext"
  Collocation -> "Collocation"

instance decodeJsonKnowledgeDimension :: DecodeJson KnowledgeDimension where
  decodeJson json = do
    value <- decodeJson json
    case knowledgeDimensionFromString value of
      Just enumValue -> pure enumValue
      Nothing -> Left (TypeMismatch "KnowledgeDimension")

instance encodeJsonKnowledgeDimension :: EncodeJson KnowledgeDimension where
  encodeJson = encodeJson <<< knowledgeDimensionToString

type UserSummary
  =
    { displayName :: String
    , email :: String
    , avatarUrl :: Maybe String
    , provider :: AuthProvider
    }

type DevLoginOption
  =
    { email :: String
    , displayName :: String
    }

type AuthConfig
  =
    { googleEnabled :: Boolean
    , googleClientId :: Maybe String
    , devLoginEnabled :: Boolean
    , devLoginOptions :: Array DevLoginOption
    }

type SessionSnapshot
  =
    { viewer :: Maybe UserSummary
    , authConfig :: AuthConfig
    }

type LearnerProfile
  =
    { learnerName :: String
    , xp :: Int
    , streakDays :: Int
    , completedLessons :: Int
    , totalLessons :: Int
    }

type DashboardStats
  =
    { dueReviews :: Int
    , currentUnitTitle :: String
    , currentUnitProgressPercent :: Int
    , accuracyPercent :: Int
    }

type LessonSummary
  =
    { lessonId :: String
    , unitId :: String
    , index :: Int
    , title :: String
    , subtitle :: String
    , goal :: String
    , xpReward :: Int
    , exerciseCount :: Int
    , status :: LessonStatus
    , masteryPercent :: Int
    }

type UnitSummary
  =
    { unitId :: String
    , index :: Int
    , title :: String
    , cefrBand :: String
    , focus :: String
    , lessonSummaries :: Array LessonSummary
    , completedLessons :: Int
    , totalLessons :: Int
    , unlocked :: Boolean
    }

type ExercisePrompt
  =
    { exerciseId :: String
    , lessonId :: String
    , kind :: ExerciseKind
    , prompt :: String
    , promptDetail :: Maybe String
    , choices :: Array String
    , fragments :: Array String
    , answerText :: Maybe String
    , acceptableAnswers :: Array String
    , translation :: Maybe String
    , hint :: Maybe String
    , explanation :: String
    }

type LessonDetail
  =
    { lesson :: LessonSummary
    , narrative :: String
    , tips :: Array String
    , exercises :: Array ExercisePrompt
    }

type ReviewSummary
  =
    { exerciseId :: String
    , lessonId :: String
    , lessonTitle :: String
    , prompt :: String
    , dueLabel :: String
    , masteryPercent :: Int
    }

type VocabularyCard
  =
    { lexemeId :: String
    , headword :: String
    , partOfSpeech :: String
    , cefrBand :: String
    , lessonId :: String
    , lessonTitle :: String
    , definition :: String
    , exampleSentence :: String
    , translation :: Maybe String
    , collocations :: Array String
    , tags :: Array String
    , masteryPercent :: Int
    , dueLabel :: String
    }

type VocabularyReviewPrompt
  =
    { reviewId :: String
    , lexemeId :: String
    , dimension :: KnowledgeDimension
    , prompt :: String
    , promptDetail :: Maybe String
    , choices :: Array String
    , answerText :: Maybe String
    , acceptableAnswers :: Array String
    , hint :: Maybe String
    , explanation :: String
    , masteryPercent :: Int
    , dueLabel :: String
    }

type VocabularyDashboard
  =
    { dueCount :: Int
    , totalTracked :: Int
    , averageMasteryPercent :: Int
    , focusWords :: Array VocabularyCard
    , reviewQueue :: Array VocabularyReviewPrompt
    }

type VocabularyReviewSubmission
  =
    { reviewId :: String
    , lexemeId :: String
    , dimension :: KnowledgeDimension
    , answerText :: Maybe String
    , selectedChoice :: Maybe String
    }

type VocabularyFeedback
  =
    { lexemeId :: String
    , dimension :: KnowledgeDimension
    , correct :: Boolean
    , explanation :: String
    , expectedAnswer :: String
    , masteryPercent :: Int
    , xpDelta :: Int
    , nextReviewHours :: Int
    }

type VocabularyReviewResult
  =
    { feedback :: VocabularyFeedback
    , profile :: LearnerProfile
    , dashboard :: VocabularyDashboard
    }

type AppBootstrap
  =
    { profile :: LearnerProfile
    , stats :: DashboardStats
    , recommendedLessonId :: Maybe String
    , reviewQueue :: Array ReviewSummary
    , vocabulary :: VocabularyDashboard
    , units :: Array UnitSummary
    }

type AttemptStart
  =
    { lessonId :: String
    }

type AttemptView
  =
    { attemptId :: String
    , lesson :: LessonSummary
    , narrative :: String
    , tips :: Array String
    , exercises :: Array ExercisePrompt
    , currentIndex :: Int
    }

type AnswerSubmission
  =
    { exerciseId :: String
    , answerText :: Maybe String
    , selectedChoices :: Array String
    , booleanAnswer :: Maybe Boolean
    }

type AnswerFeedback
  =
    { exerciseId :: String
    , correct :: Boolean
    , explanation :: String
    , expectedAnswer :: String
    , masteryPercent :: Int
    , xpDelta :: Int
    , nextReviewHours :: Int
    }

type AttemptProgress
  =
    { attemptId :: String
    , lessonId :: String
    , answeredCount :: Int
    , totalExercises :: Int
    , correctCount :: Int
    , lastFeedback :: Maybe AnswerFeedback
    , finished :: Boolean
    }

type AttemptCompletion
  =
    { attemptId :: String
    , lessonId :: String
    , lessonCompleted :: Boolean
    , xpAwarded :: Int
    , profile :: LearnerProfile
    , stats :: DashboardStats
    , newlyUnlockedLessonId :: Maybe String
    }

type GoogleAuthRequest
  =
    { credential :: String
    }

type DevLoginRequest
  =
    { email :: String
    }

type ApiError
  =
    { message :: String
    }

