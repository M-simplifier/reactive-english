{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module ReactiveEnglish.Curriculum
  ( Curriculum (..),
    CurriculumExercise (..),
    CurriculumLexeme (..),
    CurriculumLesson (..),
    CurriculumPlacementQuestion (..),
    CurriculumUnit (..),
  )
where

import Data.Aeson (FromJSON (parseJSON), withObject, (.:), (.:?))
import GHC.Generics (Generic)
import ReactiveEnglish.Schema.Generated (ExerciseKind)

data Curriculum = Curriculum
  { lexemes :: Maybe [CurriculumLexeme],
    placementQuestions :: Maybe [CurriculumPlacementQuestion],
    units :: [CurriculumUnit]
  }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON)

data CurriculumLexeme = CurriculumLexeme
  { lexemeId :: String,
    headword :: String,
    partOfSpeech :: String,
    lexemeCefrBand :: String,
    lexemeLessonId :: String,
    definition :: String,
    exampleSentence :: String,
    lexemeTranslation :: Maybe String,
    collocations :: [String],
    distractors :: [String],
    confusables :: [String],
    tags :: [String]
  }
  deriving stock (Show, Eq, Generic)

instance FromJSON CurriculumLexeme where
  parseJSON =
    withObject "CurriculumLexeme" $ \object ->
      CurriculumLexeme
        <$> object .: "lexemeId"
        <*> object .: "headword"
        <*> object .: "partOfSpeech"
        <*> object .: "cefrBand"
        <*> object .: "lessonId"
        <*> object .: "definition"
        <*> object .: "exampleSentence"
        <*> object .:? "translation"
        <*> object .: "collocations"
        <*> object .: "distractors"
        <*> object .: "confusables"
        <*> object .: "tags"

data CurriculumUnit = CurriculumUnit
  { unitId :: String,
    index :: Int,
    title :: String,
    cefrBand :: String,
    focus :: String,
    lessons :: [CurriculumLesson]
  }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON)

data CurriculumLesson = CurriculumLesson
  { lessonId :: String,
    index :: Int,
    title :: String,
    subtitle :: String,
    goal :: String,
    xpReward :: Int,
    narrative :: String,
    tips :: [String],
    exercises :: [CurriculumExercise]
  }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON)

data CurriculumExercise = CurriculumExercise
  { exerciseId :: String,
    kind :: ExerciseKind,
    prompt :: String,
    promptDetail :: Maybe String,
    choices :: [String],
    fragments :: [String],
    answerText :: Maybe String,
    acceptableAnswers :: [String],
    translation :: Maybe String,
    hint :: Maybe String,
    explanation :: String
  }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON)

data CurriculumPlacementQuestion = CurriculumPlacementQuestion
  { questionId :: String,
    placementCefrBand :: String,
    skill :: String,
    placementPrompt :: String,
    placementPromptDetail :: Maybe String,
    placementChoices :: [String],
    placementAcceptableAnswers :: [String],
    placementExplanation :: String
  }
  deriving stock (Show, Eq, Generic)

instance FromJSON CurriculumPlacementQuestion where
  parseJSON =
    withObject "CurriculumPlacementQuestion" $ \object ->
      CurriculumPlacementQuestion
        <$> object .: "questionId"
        <*> object .: "cefrBand"
        <*> object .: "skill"
        <*> object .: "prompt"
        <*> object .:? "promptDetail"
        <*> object .: "choices"
        <*> object .: "acceptableAnswers"
        <*> object .: "explanation"
