{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DuplicateRecordFields #-}

module ReactiveEnglish.Schema.Generated where

import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)

data LessonStatus = Locked | Available | InProgress | Completed deriving stock (Show, Eq, Ord, Enum, Bounded, Generic) deriving anyclass (FromJSON, ToJSON)

data AuthProvider = Google | Dev deriving stock (Show, Eq, Ord, Enum, Bounded, Generic) deriving anyclass (FromJSON, ToJSON)

data ExerciseKind = MultipleChoice | Cloze | Ordering | TrueFalse deriving stock (Show, Eq, Ord, Enum, Bounded, Generic) deriving anyclass (FromJSON, ToJSON)

data KnowledgeDimension = Recognition | MeaningRecall | FormRecall | UseInContext | Collocation deriving stock (Show, Eq, Ord, Enum, Bounded, Generic) deriving anyclass (FromJSON, ToJSON)

data UserSummary
  = UserSummary
      {displayName :: String
      , email :: String
      , avatarUrl :: Maybe String
      , provider :: AuthProvider
      }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data DevLoginOption
  = DevLoginOption
      {email :: String
      , displayName :: String
      }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data AuthConfig
  = AuthConfig
      {googleEnabled :: Bool
      , googleClientId :: Maybe String
      , devLoginEnabled :: Bool
      , devLoginOptions :: [DevLoginOption]
      }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data SessionSnapshot
  = SessionSnapshot
      {viewer :: Maybe UserSummary
      , authConfig :: AuthConfig
      }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data LearnerProfile
  = LearnerProfile
      {learnerName :: String
      , xp :: Int
      , streakDays :: Int
      , completedLessons :: Int
      , totalLessons :: Int
      }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data DashboardStats
  = DashboardStats
      {dueReviews :: Int
      , currentUnitTitle :: String
      , currentUnitProgressPercent :: Int
      , accuracyPercent :: Int
      }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data LessonSummary
  = LessonSummary
      {lessonId :: String
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
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data UnitSummary
  = UnitSummary
      {unitId :: String
      , index :: Int
      , title :: String
      , cefrBand :: String
      , focus :: String
      , lessonSummaries :: [LessonSummary]
      , completedLessons :: Int
      , totalLessons :: Int
      , unlocked :: Bool
      }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data ExercisePrompt
  = ExercisePrompt
      {exerciseId :: String
      , lessonId :: String
      , kind :: ExerciseKind
      , prompt :: String
      , promptDetail :: Maybe String
      , choices :: [String]
      , fragments :: [String]
      , answerText :: Maybe String
      , acceptableAnswers :: [String]
      , translation :: Maybe String
      , hint :: Maybe String
      , explanation :: String
      }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data LessonDetail
  = LessonDetail
      {lesson :: LessonSummary
      , narrative :: String
      , tips :: [String]
      , exercises :: [ExercisePrompt]
      }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data ReviewSummary
  = ReviewSummary
      {exerciseId :: String
      , lessonId :: String
      , lessonTitle :: String
      , prompt :: String
      , dueLabel :: String
      , masteryPercent :: Int
      }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data VocabularyCard
  = VocabularyCard
      {lexemeId :: String
      , headword :: String
      , partOfSpeech :: String
      , cefrBand :: String
      , lessonId :: String
      , lessonTitle :: String
      , definition :: String
      , exampleSentence :: String
      , translation :: Maybe String
      , collocations :: [String]
      , tags :: [String]
      , masteryPercent :: Int
      , dueLabel :: String
      }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data VocabularyReviewPrompt
  = VocabularyReviewPrompt
      {reviewId :: String
      , lexemeId :: String
      , dimension :: KnowledgeDimension
      , prompt :: String
      , promptDetail :: Maybe String
      , choices :: [String]
      , answerText :: Maybe String
      , acceptableAnswers :: [String]
      , hint :: Maybe String
      , explanation :: String
      , masteryPercent :: Int
      , dueLabel :: String
      }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data VocabularyDashboard
  = VocabularyDashboard
      {dueCount :: Int
      , totalTracked :: Int
      , averageMasteryPercent :: Int
      , focusWords :: [VocabularyCard]
      , reviewQueue :: [VocabularyReviewPrompt]
      }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data VocabularyReviewSubmission
  = VocabularyReviewSubmission
      {reviewId :: String
      , lexemeId :: String
      , dimension :: KnowledgeDimension
      , answerText :: Maybe String
      , selectedChoice :: Maybe String
      }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data VocabularyFeedback
  = VocabularyFeedback
      {lexemeId :: String
      , dimension :: KnowledgeDimension
      , correct :: Bool
      , explanation :: String
      , expectedAnswer :: String
      , masteryPercent :: Int
      , xpDelta :: Int
      , nextReviewHours :: Int
      }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data VocabularyReviewResult
  = VocabularyReviewResult
      {feedback :: VocabularyFeedback
      , profile :: LearnerProfile
      , dashboard :: VocabularyDashboard
      }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data PlacementQuestion
  = PlacementQuestion
      {questionId :: String
      , cefrBand :: String
      , skill :: String
      , prompt :: String
      , promptDetail :: Maybe String
      , choices :: [String]
      }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data PlacementAnswer
  = PlacementAnswer
      {questionId :: String
      , selectedChoice :: Maybe String
      , answerText :: Maybe String
      }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data PlacementSubmission
  = PlacementSubmission
      {answers :: [PlacementAnswer]
      }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data PlacementStatus
  = PlacementStatus
      {hasCompletedPlacement :: Bool
      , highestCefrBand :: Maybe String
      }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data AppBootstrap
  = AppBootstrap
      {profile :: LearnerProfile
      , stats :: DashboardStats
      , recommendedLessonId :: Maybe String
      , reviewQueue :: [ReviewSummary]
      , vocabulary :: VocabularyDashboard
      , placementStatus :: PlacementStatus
      , units :: [UnitSummary]
      }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data PlacementResult
  = PlacementResult
      {placedCefrBand :: String
      , scorePercent :: Int
      , xpAwarded :: Int
      , completedLessonsDelta :: Int
      , recommendedLessonId :: Maybe String
      , bootstrap :: AppBootstrap
      }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data AttemptStart
  = AttemptStart
      {lessonId :: String
      }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data AttemptView
  = AttemptView
      {attemptId :: String
      , lesson :: LessonSummary
      , narrative :: String
      , tips :: [String]
      , exercises :: [ExercisePrompt]
      , currentIndex :: Int
      }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data AnswerSubmission
  = AnswerSubmission
      {exerciseId :: String
      , answerText :: Maybe String
      , selectedChoices :: [String]
      , booleanAnswer :: Maybe Bool
      }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data AnswerFeedback
  = AnswerFeedback
      {exerciseId :: String
      , correct :: Bool
      , explanation :: String
      , expectedAnswer :: String
      , masteryPercent :: Int
      , xpDelta :: Int
      , nextReviewHours :: Int
      }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data AttemptProgress
  = AttemptProgress
      {attemptId :: String
      , lessonId :: String
      , answeredCount :: Int
      , totalExercises :: Int
      , correctCount :: Int
      , lastFeedback :: Maybe AnswerFeedback
      , finished :: Bool
      }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data AttemptCompletion
  = AttemptCompletion
      {attemptId :: String
      , lessonId :: String
      , lessonCompleted :: Bool
      , xpAwarded :: Int
      , profile :: LearnerProfile
      , stats :: DashboardStats
      , newlyUnlockedLessonId :: Maybe String
      }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data GoogleAuthRequest
  = GoogleAuthRequest
      {credential :: String
      }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data DevLoginRequest
  = DevLoginRequest
      {email :: String
      }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data ApiError
  = ApiError
      {message :: String
      }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

