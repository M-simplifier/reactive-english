{-# LANGUAGE NamedFieldPuns #-}

module ReactiveEnglish.Domain.Vocabulary
  ( VocabularyAnswerEvaluation (..),
    dimensionXpDelta,
    evaluateVocabularyReview,
    nextVocabularyMasteryPercent,
    parseKnowledgeDimension,
    renderKnowledgeDimension,
    reviewIdFor,
    submissionCandidates,
    vocabularyDimensions,
    vocabularyReviewHours,
  )
where

import Data.List (intercalate)
import Data.Maybe (catMaybes)
import ReactiveEnglish.Domain.Rules (clamp, normalizeAnswer)
import ReactiveEnglish.Schema.Generated (KnowledgeDimension (..))

data VocabularyAnswerEvaluation = VocabularyAnswerEvaluation
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

vocabularyDimensions :: [KnowledgeDimension]
vocabularyDimensions =
  [ Recognition,
    MeaningRecall,
    FormRecall,
    UseInContext,
    Collocation
  ]

evaluateVocabularyReview :: KnowledgeDimension -> [String] -> Maybe String -> Maybe String -> Int -> Int -> Int -> VocabularyAnswerEvaluation
evaluateVocabularyReview dimension acceptableAnswers selectedChoice answerText priorMastery priorCorrect priorIncorrect =
  let evaluationCandidates = submissionCandidates selectedChoice answerText
      normalizedAcceptable = map normalizeAnswer acceptableAnswers
      evaluationCorrect = any (\candidate -> normalizeAnswer candidate `elem` normalizedAcceptable) evaluationCandidates
      evaluationCorrectCount = priorCorrect + if evaluationCorrect then 1 else 0
      evaluationIncorrectCount = priorIncorrect + if evaluationCorrect then 0 else 1
      evaluationMasteryPercent = nextVocabularyMasteryPercent priorMastery evaluationCorrect
      evaluationNextReviewHours =
        if evaluationCorrect
          then vocabularyReviewHours evaluationMasteryPercent
          else 0
      evaluationXpDelta =
        if evaluationCorrect
          then dimensionXpDelta dimension
          else 0
      evaluationSubmittedAnswer = intercalate " | " evaluationCandidates
      evaluationExpectedAnswer =
        case acceptableAnswers of
          firstAnswer : remainingAnswers -> intercalate " / " (firstAnswer : remainingAnswers)
          [] -> ""
   in VocabularyAnswerEvaluation
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

submissionCandidates :: Maybe String -> Maybe String -> [String]
submissionCandidates selectedChoice answerText =
  filter (not . null . normalizeAnswer) (catMaybes [selectedChoice, answerText])

nextVocabularyMasteryPercent :: Int -> Bool -> Int
nextVocabularyMasteryPercent currentMastery correct =
  clamp 0 100 $
    if correct
      then currentMastery + 18
      else currentMastery - 12

vocabularyReviewHours :: Int -> Int
vocabularyReviewHours masteryPercentValue
  | masteryPercentValue < 20 = 6
  | masteryPercentValue < 45 = 18
  | masteryPercentValue < 70 = 48
  | masteryPercentValue < 90 = 96
  | otherwise = 240

dimensionXpDelta :: KnowledgeDimension -> Int
dimensionXpDelta Recognition = 2
dimensionXpDelta MeaningRecall = 2
dimensionXpDelta FormRecall = 3
dimensionXpDelta UseInContext = 3
dimensionXpDelta Collocation = 3

reviewIdFor :: String -> KnowledgeDimension -> String
reviewIdFor lexemeId dimension = lexemeId <> ":" <> renderKnowledgeDimension dimension

renderKnowledgeDimension :: KnowledgeDimension -> String
renderKnowledgeDimension Recognition = "Recognition"
renderKnowledgeDimension MeaningRecall = "MeaningRecall"
renderKnowledgeDimension FormRecall = "FormRecall"
renderKnowledgeDimension UseInContext = "UseInContext"
renderKnowledgeDimension Collocation = "Collocation"

parseKnowledgeDimension :: String -> Maybe KnowledgeDimension
parseKnowledgeDimension "Recognition" = Just Recognition
parseKnowledgeDimension "MeaningRecall" = Just MeaningRecall
parseKnowledgeDimension "FormRecall" = Just FormRecall
parseKnowledgeDimension "UseInContext" = Just UseInContext
parseKnowledgeDimension "Collocation" = Just Collocation
parseKnowledgeDimension _ = Nothing
