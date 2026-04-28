{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE NamedFieldPuns #-}

module ReactiveEnglish.Domain.Rules
  ( AnswerEvaluation (..),
    CompletionDecision (..),
    ShuffleSeed (..),
    advanceStreak,
    chooseCurrentUnit,
    clamp,
    decideCompletion,
    evaluateAnswer,
    findRecommendedLessonId,
    formatDay,
    isCorrectAnswer,
    lessonStatusFrom,
    nextMasteryPercent,
    normalizeAnswer,
    parseDay,
    passingAccuracy,
    percent,
    renderDueLabel,
    reviewHoursForMastery,
    shuffleAttemptOrderingFragments,
    shuffleFragmentsWithSeed,
    submittedCandidates,
    unitProgressPercent,
  )
where

import Data.Bits (xor)
import Data.Char (isSpace, ord, toLower)
import Data.List (find, foldl', intercalate, sortOn)
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Time.Calendar (Day, diffDays)
import Data.Time.Clock (NominalDiffTime, UTCTime, diffUTCTime, nominalDay)
import Data.Time.Format (defaultTimeLocale, formatTime, parseTimeM)
import ReactiveEnglish.Schema.Generated

data AnswerEvaluation = AnswerEvaluation
  { evaluationCandidates :: [String],
    evaluationSubmittedAnswer :: String,
    evaluationCorrect :: Bool,
    evaluationCorrectCount :: Int,
    evaluationIncorrectCount :: Int,
    evaluationMasteryPercent :: Int,
    evaluationNextReviewHours :: Int,
    evaluationXpDelta :: Int,
    evaluationExpectedAnswer :: String
  }
  deriving (Show, Eq)

data CompletionDecision = CompletionDecision
  { completionAccuracyPercent :: Int,
    completionPassingAttempt :: Bool,
    completionLessonCompleted :: Bool,
    completionNewlyCompleted :: Bool,
    completionBestAccuracy :: Int,
    completionXpAwarded :: Int
  }
  deriving (Show, Eq)

newtype ShuffleSeed = ShuffleSeed String
  deriving (Show, Eq, Ord)

passingAccuracy :: Int
passingAccuracy = 60

evaluateAnswer :: ExercisePrompt -> AnswerSubmission -> Int -> Int -> Int -> AnswerEvaluation
evaluateAnswer exercise submission priorMastery priorCorrect priorIncorrect =
  let evaluationCandidates = submittedCandidates exercise submission
      evaluationSubmittedAnswer = intercalate " | " evaluationCandidates
      evaluationCorrect = isCorrectAnswer exercise evaluationCandidates
      evaluationCorrectCount = priorCorrect + if evaluationCorrect then 1 else 0
      evaluationIncorrectCount = priorIncorrect + if evaluationCorrect then 0 else 1
      evaluationMasteryPercent = nextMasteryPercent priorMastery evaluationCorrect
      evaluationNextReviewHours =
        if evaluationCorrect
          then reviewHoursForMastery evaluationMasteryPercent
          else 0
      evaluationXpDelta = if evaluationCorrect then 5 else 0
      evaluationExpectedAnswer = expectedAnswerText exercise
   in AnswerEvaluation
        { evaluationCandidates,
          evaluationSubmittedAnswer,
          evaluationCorrect,
          evaluationCorrectCount,
          evaluationIncorrectCount,
          evaluationMasteryPercent,
          evaluationNextReviewHours,
          evaluationXpDelta,
          evaluationExpectedAnswer
        }

decideCompletion :: Bool -> Int -> Int -> Int -> Int -> Int -> CompletionDecision
decideCompletion alreadyCompleted previousBestAccuracy accuracyPercent correctCount totalExercises lessonXpReward =
  let completionPassingAttempt = accuracyPercent >= passingAccuracy
      completionLessonCompleted = alreadyCompleted || completionPassingAttempt
      completionNewlyCompleted = not alreadyCompleted && completionPassingAttempt
      completionBestAccuracy = max accuracyPercent previousBestAccuracy
      completionXpAwarded =
        (correctCount * 5)
          + (lessonXpReward * correctCount `div` max 1 totalExercises)
   in CompletionDecision
        { completionAccuracyPercent = accuracyPercent,
          completionPassingAttempt,
          completionLessonCompleted,
          completionNewlyCompleted,
          completionBestAccuracy,
          completionXpAwarded
        }

advanceStreak :: Day -> Int -> Maybe String -> Int
advanceStreak today currentStreak maybeLastActiveDay =
  case maybeLastActiveDay >>= parseDay of
    Nothing -> 1
    Just lastActiveDay
      | lastActiveDay == today -> max 1 currentStreak
      | diffDays today lastActiveDay == 1 -> max 1 currentStreak + 1
      | otherwise -> 1

parseDay :: String -> Maybe Day
parseDay = parseTimeM True defaultTimeLocale "%F"

formatDay :: Day -> String
formatDay = formatTime defaultTimeLocale "%F"

submittedCandidates :: ExercisePrompt -> AnswerSubmission -> [String]
submittedCandidates ExercisePrompt {kind = MultipleChoice} AnswerSubmission {selectedChoices} = selectedChoices
submittedCandidates ExercisePrompt {kind = Ordering} AnswerSubmission {selectedChoices} =
  case selectedChoices of
    [] -> []
    fragments -> [unwords fragments]
submittedCandidates ExercisePrompt {kind = Cloze} AnswerSubmission {answerText} =
  maybe [] pure answerText
submittedCandidates ExercisePrompt {kind = TrueFalse} AnswerSubmission {booleanAnswer} =
  maybe [] (\value -> [if value then "true" else "false"]) booleanAnswer

isCorrectAnswer :: ExercisePrompt -> [String] -> Bool
isCorrectAnswer ExercisePrompt {acceptableAnswers} candidateAnswers =
  let normalizedAcceptableAnswers = map normalizeAnswer acceptableAnswers
   in any (\candidate -> normalizeAnswer candidate `elem` normalizedAcceptableAnswers) candidateAnswers

expectedAnswerText :: ExercisePrompt -> String
expectedAnswerText ExercisePrompt {acceptableAnswers, answerText} =
  case acceptableAnswers of
    answer : remainingAnswers -> intercalate " / " (answer : remainingAnswers)
    [] -> fromMaybe "" answerText

normalizeAnswer :: String -> String
normalizeAnswer = unwords . words . map toLower . trim
  where
    trim = dropWhile isSpace . reverse . dropWhile isSpace . reverse

nextMasteryPercent :: Int -> Bool -> Int
nextMasteryPercent currentMastery correct =
  clamp 0 100 $
    if correct
      then currentMastery + 25
      else currentMastery - 20

reviewHoursForMastery :: Int -> Int
reviewHoursForMastery masteryPercentValue
  | masteryPercentValue < 25 = 4
  | masteryPercentValue < 50 = 12
  | masteryPercentValue < 75 = 24
  | masteryPercentValue < 100 = 72
  | otherwise = 168

lessonStatusFrom :: Maybe String -> String -> Bool -> Int -> LessonStatus
lessonStatusFrom recommendedLessonId lessonId completed alreadyAttempted
  | completed = Completed
  | Just lessonId == recommendedLessonId =
      if alreadyAttempted > 0
        then InProgress
        else Available
  | otherwise = Locked

findRecommendedLessonId :: [UnitSummary] -> Maybe String
findRecommendedLessonId unitSummaries =
  listToMaybe
    [ lessonId
      | UnitSummary {lessonSummaries} <- unitSummaries,
        LessonSummary {lessonId, status} <- lessonSummaries,
        status /= Completed
    ]

chooseCurrentUnit :: Maybe String -> [UnitSummary] -> Maybe UnitSummary
chooseCurrentUnit recommendedLessonId unitSummaries =
  case recommendedLessonId of
    Just currentLessonId ->
      find
        (\UnitSummary {lessonSummaries} -> any (\LessonSummary {lessonId} -> lessonId == currentLessonId) lessonSummaries)
        unitSummaries
    Nothing ->
      case reverse unitSummaries of
        currentUnit : _ -> Just currentUnit
        [] -> Nothing

unitProgressPercent :: UnitSummary -> Int
unitProgressPercent UnitSummary {completedLessons, totalLessons} = percent completedLessons totalLessons

shuffleAttemptOrderingFragments :: ShuffleSeed -> [ExercisePrompt] -> [ExercisePrompt]
shuffleAttemptOrderingFragments attemptSeed =
  map shuffleExercise
  where
    shuffleExercise exercise@ExercisePrompt {exerciseId, kind = Ordering, fragments} =
      exercise {fragments = shuffleFragmentsWithSeed (saltShuffleSeed attemptSeed exerciseId) fragments}
    shuffleExercise exercise = exercise

shuffleFragmentsWithSeed :: ShuffleSeed -> [String] -> [String]
shuffleFragmentsWithSeed seed fragments =
  avoidTrivialIdentity fragments shuffled
  where
    keyedFragments =
      zipWith
        (\index fragment -> ((fragmentSortKey seed index fragment, index), fragment))
        [(0 :: Int) ..]
        fragments
    shuffled = map snd (sortOn fst keyedFragments)

saltShuffleSeed :: ShuffleSeed -> String -> ShuffleSeed
saltShuffleSeed (ShuffleSeed seed) salt = ShuffleSeed (seed <> ":" <> salt)

fragmentSortKey :: ShuffleSeed -> Int -> String -> Integer
fragmentSortKey (ShuffleSeed seed) index fragment =
  hashString (seed <> ":" <> show index <> ":" <> fragment)

hashString :: String -> Integer
hashString =
  foldl'
    (\accumulator current -> (accumulator * 16777619) `xor` toInteger (ord current))
    2166136261

avoidTrivialIdentity :: [String] -> [String] -> [String]
avoidTrivialIdentity original shuffled
  | length original > 1 && shuffled == original = rotateLeft original
  | otherwise = shuffled

rotateLeft :: [a] -> [a]
rotateLeft [] = []
rotateLeft (first : rest) = rest <> [first]

renderDueLabel :: UTCTime -> UTCTime -> String
renderDueLabel now dueAt
  | dueAt <= now = "Due now"
  | hoursUntilDue <= 24 = "Due in " <> show hoursUntilDue <> "h"
  | otherwise = "Due in " <> show daysUntilDue <> "d"
  where
    secondsUntilDue = max 0 (diffUTCTimeSafe dueAt now)
    hoursUntilDue :: Int
    hoursUntilDue = ceiling (secondsUntilDue / 3600)
    daysUntilDue :: Int
    daysUntilDue = ceiling (secondsUntilDue / nominalDay)

diffUTCTimeSafe :: UTCTime -> UTCTime -> NominalDiffTime
diffUTCTimeSafe later earlier = max 0 (diffUTCTime later earlier)

percent :: Int -> Int -> Int
percent numerator denominator
  | denominator <= 0 = 0
  | otherwise = round (100 * (fromIntegral numerator / fromIntegral denominator :: Double))

clamp :: Ord a => a -> a -> a -> a
clamp minimumValue maximumValue = max minimumValue . min maximumValue
