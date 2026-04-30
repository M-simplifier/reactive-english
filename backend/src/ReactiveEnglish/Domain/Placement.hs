module ReactiveEnglish.Domain.Placement
  ( CefrLevel (..),
    allCefrLevels,
    bandPassed,
    cefrLevelForBand,
    levelRank,
    placementLevelFromBandScores,
    placementScorePercent,
    placementXpDelta,
    placementXpForLevel,
    renderCefrLevel,
    shouldCompleteLessonForPlacement,
  )
where

import Data.List (isInfixOf, sortOn)
import ReactiveEnglish.Domain.Rules (percent)

data CefrLevel
  = A1
  | A2
  | B1
  | B2
  | C1
  | C2
  deriving (Show, Eq, Ord, Enum, Bounded)

allCefrLevels :: [CefrLevel]
allCefrLevels = [minBound .. maxBound]

renderCefrLevel :: CefrLevel -> String
renderCefrLevel A1 = "A1"
renderCefrLevel A2 = "A2"
renderCefrLevel B1 = "B1"
renderCefrLevel B2 = "B2"
renderCefrLevel C1 = "C1"
renderCefrLevel C2 = "C2"

levelRank :: CefrLevel -> Int
levelRank level =
  case level of
    A1 -> 1
    A2 -> 2
    B1 -> 3
    B2 -> 4
    C1 -> 5
    C2 -> 6

cefrLevelForBand :: String -> Maybe CefrLevel
cefrLevelForBand band =
  case reverse (sortOn levelRank (filter (\level -> renderCefrLevel level `isInfixOf` band) allCefrLevels)) of
    level : _ -> Just level
    [] -> Nothing

bandPassed :: Int -> Int -> Bool
bandPassed correct total =
  total > 0 && placementScorePercent correct total >= 67

placementScorePercent :: Int -> Int -> Int
placementScorePercent = percent

placementLevelFromBandScores :: [(CefrLevel, Int, Int)] -> CefrLevel
placementLevelFromBandScores bandScores =
  case reverse (sortOn levelRank passedLevels) of
    level : _ -> level
    [] -> A1
  where
    passedLevels = [level | (level, correct, total) <- bandScores, bandPassed correct total]

placementXpForLevel :: CefrLevel -> Int
placementXpForLevel level =
  case level of
    A1 -> 0
    A2 -> 240
    B1 -> 560
    B2 -> 980
    C1 -> 1540
    C2 -> 2400

placementXpDelta :: Maybe CefrLevel -> CefrLevel -> Int
placementXpDelta previousLevel nextLevel =
  max 0 (placementXpForLevel nextLevel - maybe 0 placementXpForLevel previousLevel)

shouldCompleteLessonForPlacement :: CefrLevel -> String -> Bool
shouldCompleteLessonForPlacement placementLevel lessonBand =
  case cefrLevelForBand lessonBand of
    Nothing -> False
    Just lessonLevel -> levelRank lessonLevel < levelRank placementLevel
