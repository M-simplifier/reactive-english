{-# LANGUAGE CPP #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module ReactiveEnglish.Service
  ( ServiceError (..),
    completeAttempt,
    getBootstrap,
    getLessonDetailById,
    getPlacementQuestions,
    getReviewQueue,
    getUnitSummaryById,
    getVocabularyDashboard,
    getVocabularyReviewQueue,
    startAttempt,
    submitAnswer,
    submitPlacement,
    submitVocabularyReview,
  )
where

import Data.Aeson (decodeStrict')
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import Data.List (find, nub, sortOn)
import Data.Maybe (fromMaybe, isJust, listToMaybe, mapMaybe)
import qualified Data.Text as Text
import Data.Time.Clock (NominalDiffTime, UTCTime, addUTCTime, getCurrentTime, utctDay)
#ifdef POSTGRES_BACKEND
import qualified Database.PostgreSQL.Simple.FromRow as PGFromRow
#endif
import qualified Database.SQLite.Simple.FromRow as SQLiteFromRow
import ReactiveEnglish.Domain.Rules
  ( AnswerEvaluation (..),
    CompletionDecision (..),
    ShuffleSeed (..),
    advanceStreak,
    chooseCurrentUnit,
    decideCompletion,
    evaluateAnswer,
    findRecommendedLessonId,
    formatDay,
    lessonStatusFrom,
    normalizeAnswer,
    percent,
    renderDueLabel,
    shuffleAttemptOrderingFragments,
    shuffleFragmentsWithSeed,
    unitProgressPercent,
  )
import ReactiveEnglish.Domain.Placement
  ( CefrLevel,
    allCefrLevels,
    cefrLevelForBand,
    placementLevelFromBandScores,
    placementScorePercent,
    placementXpDelta,
    renderCefrLevel,
    shouldCompleteLessonForPlacement,
  )
import qualified ReactiveEnglish.Domain.Vocabulary as Vocabulary
import ReactiveEnglish.Db
  ( DbConnection,
    DbOnly (..),
    execute,
    insertReturningId,
    query,
    withTransaction,
  )
import ReactiveEnglish.Schema.Generated
import qualified System.Entropy as Entropy
import Text.Read (readMaybe)

data ServiceError
  = NotFoundError String
  | ConflictError String
  | ValidationError String
  deriving (Show, Eq)

type Connection = DbConnection

type Query = String

data LessonOverviewRow = LessonOverviewRow
  { rowUnitId :: String,
    rowUnitIndex :: Int,
    rowUnitTitle :: String,
    rowUnitCefrBand :: String,
    rowUnitFocus :: String,
    rowLessonId :: String,
    rowLessonIndex :: Int,
    rowLessonTitle :: String,
    rowLessonSubtitle :: String,
    rowLessonGoal :: String,
    rowLessonXpReward :: Int,
    rowLessonCompletedFlag :: Int,
    rowAttemptCount :: Int,
    rowLessonMasteryPercent :: Int,
    rowExerciseCount :: Int
  }

instance SQLiteFromRow.FromRow LessonOverviewRow where
  fromRow =
    LessonOverviewRow
      <$> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field

#ifdef POSTGRES_BACKEND
instance PGFromRow.FromRow LessonOverviewRow where
  fromRow =
    LessonOverviewRow
      <$> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
#endif

data LessonBodyRow = LessonBodyRow
  { rowBodyNarrative :: String
  }

instance SQLiteFromRow.FromRow LessonBodyRow where
  fromRow = LessonBodyRow <$> SQLiteFromRow.field

#ifdef POSTGRES_BACKEND
instance PGFromRow.FromRow LessonBodyRow where
  fromRow = LessonBodyRow <$> PGFromRow.field
#endif

data ExerciseRow = ExerciseRow
  { rowExerciseId :: String,
    rowExerciseLessonId :: String,
    rowExerciseKind :: String,
    rowExercisePrompt :: String,
    rowExercisePromptDetail :: Maybe String,
    rowExerciseChoices :: BS.ByteString,
    rowExerciseFragments :: BS.ByteString,
    rowExerciseAnswerText :: Maybe String,
    rowExerciseAcceptableAnswers :: BS.ByteString,
    rowExerciseTranslation :: Maybe String,
    rowExerciseHint :: Maybe String,
    rowExerciseExplanation :: String
  }

instance SQLiteFromRow.FromRow ExerciseRow where
  fromRow =
    ExerciseRow
      <$> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field

#ifdef POSTGRES_BACKEND
instance PGFromRow.FromRow ExerciseRow where
  fromRow =
    ExerciseRow
      <$> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
#endif

data TipRow = TipRow
  { rowTipText :: String
  }

instance SQLiteFromRow.FromRow TipRow where
  fromRow = TipRow <$> SQLiteFromRow.field

#ifdef POSTGRES_BACKEND
instance PGFromRow.FromRow TipRow where
  fromRow = TipRow <$> PGFromRow.field
#endif

data ReviewRow = ReviewRow
  { rowReviewExerciseId :: String,
    rowReviewLessonId :: String,
    rowReviewLessonTitle :: String,
    rowReviewPrompt :: String,
    rowReviewDueAt :: UTCTime,
    rowReviewMasteryPercent :: Int
  }

instance SQLiteFromRow.FromRow ReviewRow where
  fromRow =
    ReviewRow
      <$> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field

#ifdef POSTGRES_BACKEND
instance PGFromRow.FromRow ReviewRow where
  fromRow =
    ReviewRow
      <$> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
#endif

data ProfileRow = ProfileRow
  { rowLearnerName :: String,
    rowLearnerXp :: Int,
    rowLearnerStreak :: Int,
    rowLearnerLastActiveDay :: Maybe String
  }

instance SQLiteFromRow.FromRow ProfileRow where
  fromRow = ProfileRow <$> SQLiteFromRow.field <*> SQLiteFromRow.field <*> SQLiteFromRow.field <*> SQLiteFromRow.field

#ifdef POSTGRES_BACKEND
instance PGFromRow.FromRow ProfileRow where
  fromRow = ProfileRow <$> PGFromRow.field <*> PGFromRow.field <*> PGFromRow.field <*> PGFromRow.field
#endif

data AttemptRow = AttemptRow
  { rowAttemptId :: Int,
    rowAttemptLessonId :: String,
    rowAttemptTotalExercises :: Int,
    rowAttemptAnsweredCount :: Int,
    rowAttemptCorrectCount :: Int,
    rowAttemptFinishedFlag :: Int,
    rowAttemptXpAwarded :: Int,
    rowAttemptCompletedAt :: Maybe UTCTime,
    rowAttemptLessonCompletedFlag :: Int,
    rowAttemptPresentationSeed :: String
  }

instance SQLiteFromRow.FromRow AttemptRow where
  fromRow =
    AttemptRow
      <$> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field

#ifdef POSTGRES_BACKEND
instance PGFromRow.FromRow AttemptRow where
  fromRow =
    AttemptRow
      <$> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
#endif

data ExerciseProgressRow = ExerciseProgressRow
  { rowProgressCorrectCount :: Int,
    rowProgressIncorrectCount :: Int,
    rowProgressMasteryPercent :: Int
  }

instance SQLiteFromRow.FromRow ExerciseProgressRow where
  fromRow =
    ExerciseProgressRow
      <$> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field

#ifdef POSTGRES_BACKEND
instance PGFromRow.FromRow ExerciseProgressRow where
  fromRow =
    ExerciseProgressRow
      <$> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
#endif

data LessonProgressRow = LessonProgressRow
  { rowLessonProgressCompletedAt :: Maybe UTCTime,
    rowLessonProgressBestAccuracy :: Int
  }

instance SQLiteFromRow.FromRow LessonProgressRow where
  fromRow = LessonProgressRow <$> SQLiteFromRow.field <*> SQLiteFromRow.field

#ifdef POSTGRES_BACKEND
instance PGFromRow.FromRow LessonProgressRow where
  fromRow = LessonProgressRow <$> PGFromRow.field <*> PGFromRow.field
#endif

data LessonMetaRow = LessonMetaRow
  { rowLessonMetaXpReward :: Int
  }

instance SQLiteFromRow.FromRow LessonMetaRow where
  fromRow = LessonMetaRow <$> SQLiteFromRow.field

#ifdef POSTGRES_BACKEND
instance PGFromRow.FromRow LessonMetaRow where
  fromRow = LessonMetaRow <$> PGFromRow.field
#endif

data LexemeRow = LexemeRow
  { rowLexemeId :: String,
    rowLexemeLessonId :: String,
    rowLexemeLessonTitle :: String,
    rowLexemeHeadword :: String,
    rowLexemePartOfSpeech :: String,
    rowLexemeCefrBand :: String,
    rowLexemeDefinition :: String,
    rowLexemeExampleSentence :: String,
    rowLexemeTranslation :: Maybe String,
    rowLexemeCollocations :: BS.ByteString,
    rowLexemeDistractors :: BS.ByteString,
    rowLexemeConfusables :: BS.ByteString,
    rowLexemeTags :: BS.ByteString
  }

instance SQLiteFromRow.FromRow LexemeRow where
  fromRow =
    LexemeRow
      <$> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field

#ifdef POSTGRES_BACKEND
instance PGFromRow.FromRow LexemeRow where
  fromRow =
    LexemeRow
      <$> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
#endif

data LexemeProgressRow = LexemeProgressRow
  { rowLexemeProgressLexemeId :: String,
    rowLexemeProgressDimension :: String,
    rowLexemeProgressCorrectCount :: Int,
    rowLexemeProgressIncorrectCount :: Int,
    rowLexemeProgressMasteryPercent :: Int,
    rowLexemeProgressDueAt :: Maybe UTCTime
  }

instance SQLiteFromRow.FromRow LexemeProgressRow where
  fromRow =
    LexemeProgressRow
      <$> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field

#ifdef POSTGRES_BACKEND
instance PGFromRow.FromRow LexemeProgressRow where
  fromRow =
    LexemeProgressRow
      <$> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
#endif

data PlacementQuestionRow = PlacementQuestionRow
  { rowPlacementQuestionId :: String,
    rowPlacementCefrBand :: String,
    rowPlacementSkill :: String,
    rowPlacementPrompt :: String,
    rowPlacementPromptDetail :: Maybe String,
    rowPlacementChoices :: BS.ByteString,
    rowPlacementAcceptableAnswers :: BS.ByteString,
    _rowPlacementExplanation :: String
  }

instance SQLiteFromRow.FromRow PlacementQuestionRow where
  fromRow =
    PlacementQuestionRow
      <$> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field

#ifdef POSTGRES_BACKEND
instance PGFromRow.FromRow PlacementQuestionRow where
  fromRow =
    PlacementQuestionRow
      <$> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
#endif

data LessonBandRow = LessonBandRow
  { rowBandLessonId :: String,
    rowBandCefrBand :: String
  }

instance SQLiteFromRow.FromRow LessonBandRow where
  fromRow = LessonBandRow <$> SQLiteFromRow.field <*> SQLiteFromRow.field

#ifdef POSTGRES_BACKEND
instance PGFromRow.FromRow LessonBandRow where
  fromRow = LessonBandRow <$> PGFromRow.field <*> PGFromRow.field
#endif

data PlacementResultRow = PlacementResultRow
  { rowPlacementResultBand :: String
  }

instance SQLiteFromRow.FromRow PlacementResultRow where
  fromRow = PlacementResultRow <$> SQLiteFromRow.field

#ifdef POSTGRES_BACKEND
instance PGFromRow.FromRow PlacementResultRow where
  fromRow = PlacementResultRow <$> PGFromRow.field
#endif

getBootstrap :: Connection -> Int -> IO AppBootstrap
getBootstrap connection userIdValue = do
  unitSummaries <- loadUnitSummaries connection userIdValue
  reviewQueue <- loadReviewSummaries connection userIdValue 5
  vocabularyDashboard <- getVocabularyDashboard connection userIdValue
  dueReviewCount <- loadDueReviewCount connection userIdValue
  accuracyPercent <- loadAccuracyPercent connection userIdValue
  ProfileRow {rowLearnerName, rowLearnerXp, rowLearnerStreak} <- loadProfileRow connection userIdValue
  let completedLessonCount = sum (map unitCompletedLessons unitSummaries)
      totalLessonCount = sum (map unitTotalLessons unitSummaries)
      recommendedLessonValue = findRecommendedLessonId unitSummaries
      currentUnit = chooseCurrentUnit recommendedLessonValue unitSummaries
      stats =
        DashboardStats
          { dueReviews = dueReviewCount,
            currentUnitTitle = maybe "" unitTitle currentUnit,
            currentUnitProgressPercent = maybe 0 unitProgressPercent currentUnit,
            accuracyPercent = accuracyPercent
          }
      profile =
        LearnerProfile
          { learnerName = rowLearnerName,
            xp = rowLearnerXp,
            streakDays = rowLearnerStreak,
            completedLessons = completedLessonCount,
            totalLessons = totalLessonCount
          }
  pure
    AppBootstrap
      { profile = profile,
        stats = stats,
        recommendedLessonId = recommendedLessonValue,
        reviewQueue = reviewQueue,
        vocabulary = vocabularyDashboard,
        units = unitSummaries
      }

getUnitSummaryById :: Connection -> Int -> String -> IO (Maybe UnitSummary)
getUnitSummaryById connection userIdValue requestedUnitId =
  find (\UnitSummary {unitId} -> unitId == requestedUnitId) <$> loadUnitSummaries connection userIdValue

getLessonDetailById :: Connection -> Int -> String -> IO (Maybe LessonDetail)
getLessonDetailById connection userIdValue requestedLessonId = do
  unitSummaries <- loadUnitSummaries connection userIdValue
  lessonSummary <- pure (findLessonSummary requestedLessonId unitSummaries)
  lessonBody <- loadLessonBody connection requestedLessonId
  case (lessonSummary, lessonBody) of
    (Just summary, Just (narrativeText, lessonTips, lessonExercises)) ->
      pure
        ( Just
            LessonDetail
              { lesson = summary,
                narrative = narrativeText,
                tips = lessonTips,
                exercises = lessonExercises
              }
        )
    _ -> pure Nothing

getReviewQueue :: Connection -> Int -> IO [ReviewSummary]
getReviewQueue connection userIdValue = loadReviewSummaries connection userIdValue 20

getPlacementQuestions :: Connection -> Int -> IO [PlacementQuestion]
getPlacementQuestions connection _userIdValue =
  map toPlacementQuestion <$> loadPlacementQuestionRows connection

submitPlacement :: Connection -> Int -> PlacementSubmission -> IO (Either ServiceError PlacementResult)
submitPlacement connection userIdValue PlacementSubmission {answers = submittedAnswers} = do
  outcome <- withTransaction connection $ do
    questionRows <- loadPlacementQuestionRows connection
    if null questionRows
      then pure (Left (ValidationError "Placement test is not configured in this curriculum."))
      else do
        now <- getCurrentTime
        let scoredRows = map (scorePlacementQuestion submittedAnswers) questionRows
            correctCount = length (filter snd scoredRows)
            totalQuestions = length questionRows
            bandScores =
              [ (level, correctFor level scoredRows, totalFor level scoredRows)
                | level <- allCefrLevels
              ]
            placedLevel = placementLevelFromBandScores bandScores
            scorePercentValue = placementScorePercent correctCount totalQuestions
        previousLevel <- loadHighestPlacementLevel connection userIdValue
        let xpDelta = placementXpDelta previousLevel placedLevel
        completedBefore <- loadCompletedLessonCount connection userIdValue
        markLessonsCompletedForPlacement connection userIdValue placedLevel scorePercentValue now
        completedAfter <- loadCompletedLessonCount connection userIdValue
        applyCompletionRewards connection userIdValue xpDelta now
        execute
          connection
          "INSERT INTO user_placement_results (user_id, placed_cefr_band, score_percent, correct_count, total_questions, xp_awarded, completed_lessons_delta, submitted_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
          ( userIdValue,
            renderCefrLevel placedLevel,
            scorePercentValue,
            correctCount,
            totalQuestions,
            xpDelta,
            max 0 (completedAfter - completedBefore),
            now
          )
        pure
          ( Right
              ( renderCefrLevel placedLevel,
                scorePercentValue,
                xpDelta,
                max 0 (completedAfter - completedBefore)
              )
          )
  case outcome of
    Left serviceError -> pure (Left serviceError)
    Right (placedBand, scorePercentValue, xpDelta, completedLessonsDeltaValue) -> do
      bootstrap <- getBootstrap connection userIdValue
      pure
        ( Right
            PlacementResult
              { placedCefrBand = placedBand,
                scorePercent = scorePercentValue,
                xpAwarded = xpDelta,
                completedLessonsDelta = completedLessonsDeltaValue,
                recommendedLessonId = bootstrapRecommendedLessonId bootstrap,
                bootstrap = bootstrap
              }
        )

getVocabularyDashboard :: Connection -> Int -> IO VocabularyDashboard
getVocabularyDashboard connection userIdValue = do
  lexemeRows <- loadLexemeRows connection
  progressRows <- loadLexemeProgressRows connection userIdValue
  now <- getCurrentTime
  let cards = map (buildVocabularyCard now progressRows) lexemeRows
      reviewPrompts = take 5 (buildVocabularyReviewPrompts now progressRows lexemeRows)
      allMasteries =
        [ vocabularyDimensionMastery progressRows (rowLexemeId lexemeRow) dimension
          | lexemeRow <- lexemeRows,
            dimension <- Vocabulary.vocabularyDimensions
        ]
      averageMastery =
        case allMasteries of
          [] -> 0
          values -> percent (sum values) (length values)
      focusWords = take 6 (sortOn vocabularyCardMastery cards)
  pure
    VocabularyDashboard
      { dueCount = length (buildVocabularyReviewPrompts now progressRows lexemeRows),
        totalTracked = length lexemeRows,
        averageMasteryPercent = averageMastery,
        focusWords = focusWords,
        reviewQueue = reviewPrompts
      }

getVocabularyReviewQueue :: Connection -> Int -> IO [VocabularyReviewPrompt]
getVocabularyReviewQueue connection userIdValue = do
  lexemeRows <- loadLexemeRows connection
  progressRows <- loadLexemeProgressRows connection userIdValue
  now <- getCurrentTime
  pure (take 20 (buildVocabularyReviewPrompts now progressRows lexemeRows))

submitVocabularyReview :: Connection -> Int -> VocabularyReviewSubmission -> IO (Either ServiceError VocabularyReviewResult)
submitVocabularyReview connection userIdValue VocabularyReviewSubmission {reviewId = submittedReviewId, lexemeId = submittedLexemeId, dimension = submittedDimension, answerText, selectedChoice} = do
  result <- withTransaction connection $ do
    maybeLexeme <- loadLexemeById connection submittedLexemeId
    case maybeLexeme of
      Nothing -> pure (Left (NotFoundError ("Unknown vocabulary item: " <> submittedLexemeId)))
      Just lexemeRow -> do
        if submittedReviewId /= Vocabulary.reviewIdFor submittedLexemeId submittedDimension
          then pure (Left (ValidationError ("Vocabulary review id does not match submitted item: " <> submittedReviewId)))
          else do
            now <- getCurrentTime
            progressRows <- loadLexemeProgressRows connection userIdValue
            let priorProgress = progressFor progressRows submittedLexemeId submittedDimension
                priorMastery = maybe 0 rowLexemeProgressMasteryPercent priorProgress
                priorCorrect = maybe 0 rowLexemeProgressCorrectCount priorProgress
                priorIncorrect = maybe 0 rowLexemeProgressIncorrectCount priorProgress
                prompt = buildVocabularyReviewPrompt now priorProgress lexemeRow submittedDimension
                evaluation =
                  Vocabulary.evaluateVocabularyReview
                    submittedDimension
                    (vocabularyPromptAcceptableAnswers prompt)
                    selectedChoice
                    answerText
                    priorMastery
                    priorCorrect
                    priorIncorrect
                dueAt =
                  if Vocabulary.evaluationCorrect evaluation
                    then Just (addUTCTime (hoursToDiff (Vocabulary.evaluationNextReviewHours evaluation)) now)
                    else Just now
                dimensionText = Vocabulary.renderKnowledgeDimension submittedDimension
            execute
              connection
              "INSERT INTO user_lexeme_review_events (user_id, lexeme_id, dimension, submitted_answer, is_correct, mastery_percent, xp_delta, reviewed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
              ( userIdValue,
                submittedLexemeId,
                dimensionText,
                Vocabulary.evaluationSubmittedAnswer evaluation,
                boolToInt (Vocabulary.evaluationCorrect evaluation),
                Vocabulary.evaluationMasteryPercent evaluation,
                Vocabulary.evaluationXpDelta evaluation,
                now
              )
            execute
              connection
              "INSERT INTO user_lexeme_progress (user_id, lexeme_id, dimension, correct_count, incorrect_count, mastery_percent, due_at, last_reviewed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT (user_id, lexeme_id, dimension) DO UPDATE SET correct_count = excluded.correct_count, incorrect_count = excluded.incorrect_count, mastery_percent = excluded.mastery_percent, due_at = excluded.due_at, last_reviewed_at = excluded.last_reviewed_at"
              ( userIdValue,
                submittedLexemeId,
                dimensionText,
                Vocabulary.evaluationCorrectCount evaluation,
                Vocabulary.evaluationIncorrectCount evaluation,
                Vocabulary.evaluationMasteryPercent evaluation,
                dueAt,
                now
              )
            applyCompletionRewards connection userIdValue (Vocabulary.evaluationXpDelta evaluation) now
            pure
              ( Right
                  VocabularyFeedback
                    { lexemeId = submittedLexemeId,
                      dimension = submittedDimension,
                      correct = Vocabulary.evaluationCorrect evaluation,
                      explanation = vocabularyPromptExplanation prompt,
                      expectedAnswer = Vocabulary.evaluationExpectedAnswer evaluation,
                      masteryPercent = Vocabulary.evaluationMasteryPercent evaluation,
                      xpDelta = Vocabulary.evaluationXpDelta evaluation,
                      nextReviewHours = Vocabulary.evaluationNextReviewHours evaluation
                    }
              )
  case result of
    Left serviceError -> pure (Left serviceError)
    Right feedback -> do
      bootstrap <- getBootstrap connection userIdValue
      pure
        ( Right
            VocabularyReviewResult
              { feedback = feedback,
                profile = bootstrapProfile bootstrap,
                dashboard = bootstrapVocabulary bootstrap
              }
        )

startAttempt :: Connection -> Int -> AttemptStart -> IO (Either ServiceError AttemptView)
startAttempt connection userIdValue AttemptStart {lessonId = requestedLessonId} = do
  maybeLessonDetail <- getLessonDetailById connection userIdValue requestedLessonId
  case maybeLessonDetail of
    Nothing -> pure (Left (NotFoundError ("Unknown lesson: " <> requestedLessonId)))
    Just LessonDetail {lesson = lessonSummary, narrative = narrativeText, tips = lessonTips, exercises = lessonExercises} ->
      if lessonSummaryStatus lessonSummary == Locked
        then pure (Left (ConflictError ("Lesson is still locked: " <> requestedLessonId)))
        else do
          existingAttempt <- loadOpenAttemptForLesson connection userIdValue requestedLessonId
          (attemptIdentifier, currentIndexValue, presentationSeed) <-
            case existingAttempt of
              Just AttemptRow {rowAttemptId, rowAttemptAnsweredCount, rowAttemptPresentationSeed} ->
                pure (show rowAttemptId, rowAttemptAnsweredCount, nonEmptyPresentationSeed rowAttemptId rowAttemptPresentationSeed)
              Nothing -> do
                now <- getCurrentTime
                generatedPresentationSeed <- generatePresentationSeed
                withTransaction connection $ do
                  insertedId <-
                    insertReturningId
                    connection
                    "INSERT INTO user_attempts (user_id, lesson_id, started_at, completed_at, total_exercises, answered_count, correct_count, finished, xp_awarded, lesson_completed, presentation_seed) VALUES (?, ?, ?, NULL, ?, 0, 0, 0, 0, 0, ?)"
                    "INSERT INTO user_attempts (user_id, lesson_id, started_at, completed_at, total_exercises, answered_count, correct_count, finished, xp_awarded, lesson_completed, presentation_seed) VALUES (?, ?, ?, NULL, ?, 0, 0, 0, 0, 0, ?) RETURNING attempt_id"
                    (userIdValue, requestedLessonId, now, length lessonExercises, generatedPresentationSeed)
                  execute
                    connection
                    "INSERT INTO user_lesson_progress (user_id, lesson_id, completed_at, best_accuracy, last_attempted_at, total_attempts) VALUES (?, ?, NULL, 0, ?, 1) ON CONFLICT (user_id, lesson_id) DO UPDATE SET last_attempted_at = excluded.last_attempted_at, total_attempts = user_lesson_progress.total_attempts + 1"
                    (userIdValue, requestedLessonId, now)
                  pure (show insertedId, 0, generatedPresentationSeed)
          let sessionLesson =
                if lessonSummaryStatus lessonSummary == Completed
                  then lessonSummary
                  else lessonSummary {status = InProgress}
              presentedExercises =
                shuffleAttemptOrderingFragments (ShuffleSeed (attemptIdentifier <> ":" <> presentationSeed)) lessonExercises
          pure
            ( Right
                AttemptView
                  { attemptId = attemptIdentifier,
                    lesson = sessionLesson,
                    narrative = narrativeText,
                    tips = lessonTips,
                    exercises = presentedExercises,
                    currentIndex = currentIndexValue
                  }
            )

submitAnswer :: Connection -> Int -> String -> AnswerSubmission -> IO (Either ServiceError AttemptProgress)
submitAnswer connection userIdValue attemptIdText submission =
  case parseAttemptIdentifier attemptIdText of
    Left serviceError -> pure (Left serviceError)
    Right attemptIdValue ->
      withTransaction connection $ do
        maybeAttempt <- loadAttemptById connection userIdValue attemptIdValue
        case maybeAttempt of
          Nothing -> pure (Left (NotFoundError ("Unknown attempt: " <> attemptIdText)))
          Just AttemptRow {rowAttemptLessonId, rowAttemptTotalExercises, rowAttemptAnsweredCount, rowAttemptCorrectCount, rowAttemptFinishedFlag} ->
            if rowAttemptFinishedFlag /= 0
              then pure (Left (ConflictError ("Attempt is already finished: " <> attemptIdText)))
              else do
                maybeLessonBody <- loadLessonBody connection rowAttemptLessonId
                case maybeLessonBody of
                  Nothing -> pure (Left (NotFoundError ("Unknown lesson for attempt: " <> rowAttemptLessonId)))
                  Just (_, _, orderedExercises) ->
                    if rowAttemptAnsweredCount >= length orderedExercises
                      then pure (Left (ConflictError ("Attempt has no remaining exercises: " <> attemptIdText)))
                      else do
                        let expectedExercise = orderedExercises !! rowAttemptAnsweredCount
                            expectedExerciseId = exercisePromptId expectedExercise
                            submittedExerciseId = answerSubmissionExerciseId submission
                        if submittedExerciseId /= expectedExerciseId
                          then pure (Left (ConflictError ("Expected exercise " <> expectedExerciseId <> " for attempt " <> attemptIdText)))
                          else do
                            now <- getCurrentTime
                            currentExerciseProgress <- loadExerciseProgress connection userIdValue expectedExerciseId
                            let priorMastery = maybe 0 rowProgressMasteryPercent currentExerciseProgress
                                priorCorrect = maybe 0 rowProgressCorrectCount currentExerciseProgress
                                priorIncorrect = maybe 0 rowProgressIncorrectCount currentExerciseProgress
                                evaluation =
                                  evaluateAnswer expectedExercise submission priorMastery priorCorrect priorIncorrect
                                dueAt =
                                  if evaluationCorrect evaluation
                                    then Just (addUTCTime (hoursToDiff (evaluationNextReviewHours evaluation)) now)
                                    else Just now
                                feedback =
                                  AnswerFeedback
                                    { exerciseId = expectedExerciseId,
                                      correct = evaluationCorrect evaluation,
                                      explanation = exercisePromptExplanation expectedExercise,
                                      expectedAnswer = evaluationExpectedAnswer evaluation,
                                      masteryPercent = evaluationMasteryPercent evaluation,
                                      xpDelta = evaluationXpDelta evaluation,
                                      nextReviewHours = evaluationNextReviewHours evaluation
                                    }
                                newAnsweredCount = rowAttemptAnsweredCount + 1
                                newCorrectCount = rowAttemptCorrectCount + if evaluationCorrect evaluation then 1 else 0
                                finishedFlag :: Int
                                finishedFlag = if newAnsweredCount >= rowAttemptTotalExercises then 1 else 0
                            execute
                              connection
                              "INSERT INTO user_attempt_answers (user_id, attempt_id, exercise_id, submitted_answer, is_correct, submitted_at) VALUES (?, ?, ?, ?, ?, ?)"
                              (userIdValue, attemptIdValue, expectedExerciseId, evaluationSubmittedAnswer evaluation, boolToInt (evaluationCorrect evaluation), now)
                            execute
                              connection
                              "INSERT INTO user_exercise_progress (user_id, exercise_id, correct_count, incorrect_count, mastery_percent, due_at, last_answered_at) VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT (user_id, exercise_id) DO UPDATE SET correct_count = excluded.correct_count, incorrect_count = excluded.incorrect_count, mastery_percent = excluded.mastery_percent, due_at = excluded.due_at, last_answered_at = excluded.last_answered_at"
                              ( userIdValue,
                                expectedExerciseId,
                                evaluationCorrectCount evaluation,
                                evaluationIncorrectCount evaluation,
                                evaluationMasteryPercent evaluation,
                                dueAt,
                                now
                              )
                            execute
                              connection
                              "UPDATE user_attempts SET answered_count = ?, correct_count = ?, finished = ? WHERE attempt_id = ? AND user_id = ?"
                              (newAnsweredCount, newCorrectCount, finishedFlag, attemptIdValue, userIdValue)
                            pure
                              ( Right
                                  AttemptProgress
                                    { attemptId = attemptIdText,
                                      lessonId = rowAttemptLessonId,
                                      answeredCount = newAnsweredCount,
                                      totalExercises = rowAttemptTotalExercises,
                                      correctCount = newCorrectCount,
                                      lastFeedback = Just feedback,
                                      finished = finishedFlag /= 0
                                    }
                              )

completeAttempt :: Connection -> Int -> String -> IO (Either ServiceError AttemptCompletion)
completeAttempt connection userIdValue attemptIdText =
  case parseAttemptIdentifier attemptIdText of
    Left serviceError -> pure (Left serviceError)
    Right attemptIdValue -> do
      completionResult <- withTransaction connection $ do
        maybeAttempt <- loadAttemptById connection userIdValue attemptIdValue
        case maybeAttempt of
          Nothing -> pure (Left (NotFoundError ("Unknown attempt: " <> attemptIdText)))
          Just AttemptRow {rowAttemptLessonId, rowAttemptTotalExercises, rowAttemptAnsweredCount, rowAttemptCorrectCount, rowAttemptXpAwarded, rowAttemptCompletedAt, rowAttemptLessonCompletedFlag} ->
            if rowAttemptAnsweredCount < rowAttemptTotalExercises
              then pure (Left (ConflictError ("Attempt is not finished yet: " <> attemptIdText)))
              else
                case rowAttemptCompletedAt of
                  Just _ ->
                    pure
                      ( Right
                          CompletionSnapshot
                            { snapshotLessonId = rowAttemptLessonId,
                              snapshotLessonCompleted = rowAttemptLessonCompletedFlag /= 0,
                              snapshotXpAwarded = rowAttemptXpAwarded,
                              snapshotNewlyUnlocked = False
                            }
                      )
                  Nothing -> do
                    maybeLessonMeta <- loadLessonMeta connection rowAttemptLessonId
                    case maybeLessonMeta of
                      Nothing -> pure (Left (NotFoundError ("Unknown lesson for attempt: " <> rowAttemptLessonId)))
                      Just LessonMetaRow {rowLessonMetaXpReward} -> do
                        now <- getCurrentTime
                        lessonProgress <- loadLessonProgress connection userIdValue rowAttemptLessonId
                        let accuracyPercent = percent rowAttemptCorrectCount rowAttemptTotalExercises
                            alreadyCompleted = maybe False (isJust . rowLessonProgressCompletedAt) lessonProgress
                            decision =
                              decideCompletion
                                alreadyCompleted
                                (maybe 0 rowLessonProgressBestAccuracy lessonProgress)
                                accuracyPercent
                                rowAttemptCorrectCount
                                rowAttemptTotalExercises
                                rowLessonMetaXpReward
                            completedAtValue =
                              if completionLessonCompleted decision
                                then Just (maybe now id (lessonProgress >>= rowLessonProgressCompletedAt))
                                else Nothing
                        execute
                          connection
                          "UPDATE user_attempts SET completed_at = ?, xp_awarded = ?, lesson_completed = ?, finished = 1 WHERE attempt_id = ? AND user_id = ?"
                          ( now,
                            completionXpAwarded decision,
                            boolToInt (completionLessonCompleted decision),
                            attemptIdValue,
                            userIdValue
                          )
                        execute
                          connection
                          "INSERT INTO user_lesson_progress (user_id, lesson_id, completed_at, best_accuracy, last_attempted_at, total_attempts) VALUES (?, ?, ?, ?, ?, 0) ON CONFLICT (user_id, lesson_id) DO UPDATE SET completed_at = excluded.completed_at, best_accuracy = excluded.best_accuracy, last_attempted_at = excluded.last_attempted_at"
                          (userIdValue, rowAttemptLessonId, completedAtValue, completionBestAccuracy decision, now)
                        applyCompletionRewards connection userIdValue (completionXpAwarded decision) now
                        pure
                          ( Right
                              CompletionSnapshot
                                { snapshotLessonId = rowAttemptLessonId,
                                  snapshotLessonCompleted = completionLessonCompleted decision,
                                  snapshotXpAwarded = completionXpAwarded decision,
                                  snapshotNewlyUnlocked = completionNewlyCompleted decision
                                }
                          )

      case completionResult of
        Left serviceError -> pure (Left serviceError)
        Right CompletionSnapshot {snapshotLessonId, snapshotLessonCompleted, snapshotXpAwarded, snapshotNewlyUnlocked} -> do
          bootstrap <- getBootstrap connection userIdValue
          pure
            ( Right
                AttemptCompletion
                  { attemptId = attemptIdText,
                    lessonId = snapshotLessonId,
                    lessonCompleted = snapshotLessonCompleted,
                    xpAwarded = snapshotXpAwarded,
                    profile = bootstrapProfile bootstrap,
                    stats = bootstrapStats bootstrap,
                    newlyUnlockedLessonId =
                      if snapshotNewlyUnlocked
                        then bootstrapRecommendedLessonId bootstrap
                        else Nothing
                  }
            )

data CompletionSnapshot = CompletionSnapshot
  { snapshotLessonId :: String,
    snapshotLessonCompleted :: Bool,
    snapshotXpAwarded :: Int,
    snapshotNewlyUnlocked :: Bool
  }

loadUnitSummaries :: Connection -> Int -> IO [UnitSummary]
loadUnitSummaries connection userIdValue = do
  lessonRows <- query connection lessonOverviewQuery (userIdValue, userIdValue)
  let recommendedLessonValue = listToMaybe [rowLessonId row | row <- lessonRows, rowLessonCompletedFlag row == 0]
      groupedRows = groupLessonRows lessonRows
  pure (map (buildUnitSummary recommendedLessonValue) groupedRows)

lessonOverviewQuery :: Query
lessonOverviewQuery =
  "SELECT u.unit_id, u.sort_index, u.title, u.cefr_band, u.focus, l.lesson_id, l.sort_index, l.title, l.subtitle, l.goal, l.xp_reward, CASE WHEN lp.completed_at IS NULL THEN 0 ELSE 1 END AS lesson_completed, COALESCE(lp.total_attempts, 0) AS total_attempts, COALESCE(CAST(ROUND(AVG(COALESCE(ep.mastery_percent, 0))) AS INTEGER), 0) AS lesson_mastery_percent, COUNT(e.exercise_id) AS exercise_count FROM units u JOIN lessons l ON l.unit_id = u.unit_id LEFT JOIN user_lesson_progress lp ON lp.lesson_id = l.lesson_id AND lp.user_id = ? LEFT JOIN exercises e ON e.lesson_id = l.lesson_id LEFT JOIN user_exercise_progress ep ON ep.exercise_id = e.exercise_id AND ep.user_id = ? GROUP BY u.unit_id, u.sort_index, u.title, u.cefr_band, u.focus, l.lesson_id, l.sort_index, l.title, l.subtitle, l.goal, l.xp_reward, lp.completed_at, lp.total_attempts ORDER BY u.sort_index, l.sort_index"

groupLessonRows :: [LessonOverviewRow] -> [(LessonOverviewRow, [LessonOverviewRow])]
groupLessonRows [] = []
groupLessonRows (firstRow : remainingRows) =
  let (sameUnitRows, otherRows) = span (\row -> rowUnitId row == rowUnitId firstRow) remainingRows
   in (firstRow, firstRow : sameUnitRows) : groupLessonRows otherRows

buildUnitSummary :: Maybe String -> (LessonOverviewRow, [LessonOverviewRow]) -> UnitSummary
buildUnitSummary recommendedLessonId (unitRow, lessonRows) =
  let lessonSummaries =
        map
          (\row ->
             LessonSummary
               { lessonId = rowLessonId row,
                 unitId = rowUnitId row,
                 index = rowLessonIndex row,
                 title = rowLessonTitle row,
                 subtitle = rowLessonSubtitle row,
                 goal = rowLessonGoal row,
                 xpReward = rowLessonXpReward row,
                 exerciseCount = rowExerciseCount row,
                 status = lessonStatus recommendedLessonId row,
                 masteryPercent = rowLessonMasteryPercent row
               }
          )
          lessonRows
      completedCount = length (filter (\row -> rowLessonCompletedFlag row /= 0) lessonRows)
   in UnitSummary
        { unitId = rowUnitId unitRow,
          index = rowUnitIndex unitRow,
          title = rowUnitTitle unitRow,
          cefrBand = rowUnitCefrBand unitRow,
          focus = rowUnitFocus unitRow,
          lessonSummaries = lessonSummaries,
          completedLessons = completedCount,
          totalLessons = length lessonRows,
          unlocked = any ((/= Locked) . status) lessonSummaries
        }

lessonStatus :: Maybe String -> LessonOverviewRow -> LessonStatus
lessonStatus recommendedLessonId row
  =
    lessonStatusFrom
      recommendedLessonId
      (rowLessonId row)
      (rowLessonCompletedFlag row /= 0)
      (rowAttemptCount row)

findLessonSummary :: String -> [UnitSummary] -> Maybe LessonSummary
findLessonSummary requestedLessonId unitSummaries =
  listToMaybe
    [ lessonSummary
      | unitSummary <- unitSummaries,
        lessonSummary <- unitLessonSummaries unitSummary,
        lessonSummaryId lessonSummary == requestedLessonId
    ]

loadLessonBody :: Connection -> String -> IO (Maybe (String, [String], [ExercisePrompt]))
loadLessonBody connection requestedLessonId = do
  lessonRows <- query connection "SELECT narrative FROM lessons WHERE lesson_id = ?" (DbOnly requestedLessonId)
  case lessonRows of
    [] -> pure Nothing
    LessonBodyRow {rowBodyNarrative} : _ -> do
      tipRows <- query connection "SELECT tip FROM lesson_tips WHERE lesson_id = ? ORDER BY sort_index" (DbOnly requestedLessonId)
      exerciseRows <- query connection exerciseByLessonQuery (DbOnly requestedLessonId)
      pure (Just (rowBodyNarrative, map rowTipText tipRows, map toExercisePrompt exerciseRows))

exerciseByLessonQuery :: Query
exerciseByLessonQuery =
  "SELECT exercise_id, lesson_id, kind, prompt, prompt_detail, choices_json, fragments_json, answer_text, acceptable_answers_json, translation, hint, explanation FROM exercises WHERE lesson_id = ? ORDER BY sort_index"

toExercisePrompt :: ExerciseRow -> ExercisePrompt
toExercisePrompt ExerciseRow {rowExerciseId, rowExerciseLessonId, rowExerciseKind, rowExercisePrompt, rowExercisePromptDetail, rowExerciseChoices, rowExerciseFragments, rowExerciseAnswerText, rowExerciseAcceptableAnswers, rowExerciseTranslation, rowExerciseHint, rowExerciseExplanation} =
  ExercisePrompt
    { exerciseId = rowExerciseId,
      lessonId = rowExerciseLessonId,
      kind = parseExerciseKind rowExerciseKind,
      prompt = rowExercisePrompt,
      promptDetail = rowExercisePromptDetail,
      choices = decodeList rowExerciseChoices,
      fragments = decodeList rowExerciseFragments,
      answerText = rowExerciseAnswerText,
      acceptableAnswers = decodeList rowExerciseAcceptableAnswers,
      translation = rowExerciseTranslation,
      hint = rowExerciseHint,
      explanation = rowExerciseExplanation
    }

parseExerciseKind :: String -> ExerciseKind
parseExerciseKind "MultipleChoice" = MultipleChoice
parseExerciseKind "Cloze" = Cloze
parseExerciseKind "Ordering" = Ordering
parseExerciseKind "TrueFalse" = TrueFalse
parseExerciseKind unknownKind = errorWithoutStackTrace ("Unknown exercise kind in database: " <> unknownKind)

decodeList :: BS.ByteString -> [String]
decodeList encoded =
  fromMaybe
    (errorWithoutStackTrace "Invalid encoded list in SQLite seed data")
    (decodeStrict' encoded)

loadLexemeRows :: Connection -> IO [LexemeRow]
loadLexemeRows connection =
  query
    connection
    "SELECT lx.lexeme_id, lx.lesson_id, l.title, lx.headword, lx.part_of_speech, lx.cefr_band, lx.definition, lx.example_sentence, lx.translation, lx.collocations_json, lx.distractors_json, lx.confusables_json, lx.tags_json FROM lexemes lx JOIN lessons l ON l.lesson_id = lx.lesson_id ORDER BY l.unit_id, l.sort_index, lx.lexeme_id"
    ()

loadLexemeById :: Connection -> String -> IO (Maybe LexemeRow)
loadLexemeById connection requestedLexemeId = do
  rows <-
    query
      connection
      "SELECT lx.lexeme_id, lx.lesson_id, l.title, lx.headword, lx.part_of_speech, lx.cefr_band, lx.definition, lx.example_sentence, lx.translation, lx.collocations_json, lx.distractors_json, lx.confusables_json, lx.tags_json FROM lexemes lx JOIN lessons l ON l.lesson_id = lx.lesson_id WHERE lx.lexeme_id = ?"
      (DbOnly requestedLexemeId)
  pure (listToMaybe rows)

loadLexemeProgressRows :: Connection -> Int -> IO [LexemeProgressRow]
loadLexemeProgressRows connection userIdValue =
  query
    connection
    "SELECT lexeme_id, dimension, correct_count, incorrect_count, mastery_percent, due_at FROM user_lexeme_progress WHERE user_id = ?"
    (DbOnly userIdValue)

loadPlacementQuestionRows :: Connection -> IO [PlacementQuestionRow]
loadPlacementQuestionRows connection =
  query
    connection
    "SELECT question_id, cefr_band, skill, prompt, prompt_detail, choices_json, acceptable_answers_json, explanation FROM placement_questions ORDER BY cefr_band, question_id"
    ()

toPlacementQuestion :: PlacementQuestionRow -> PlacementQuestion
toPlacementQuestion PlacementQuestionRow {rowPlacementQuestionId, rowPlacementCefrBand, rowPlacementSkill, rowPlacementPrompt, rowPlacementPromptDetail, rowPlacementChoices} =
  PlacementQuestion
    { questionId = rowPlacementQuestionId,
      cefrBand = rowPlacementCefrBand,
      skill = rowPlacementSkill,
      prompt = rowPlacementPrompt,
      promptDetail = rowPlacementPromptDetail,
      choices = decodeList rowPlacementChoices
    }

scorePlacementQuestion :: [PlacementAnswer] -> PlacementQuestionRow -> (PlacementQuestionRow, Bool)
scorePlacementQuestion submittedAnswers questionRow@PlacementQuestionRow {rowPlacementQuestionId, rowPlacementAcceptableAnswers} =
  let accepted = map normalizeAnswer (decodeList rowPlacementAcceptableAnswers)
      candidates =
        case findPlacementAnswer rowPlacementQuestionId submittedAnswers of
          Nothing -> []
          Just PlacementAnswer {selectedChoice, answerText} ->
            filter (not . null) (map normalizeAnswer (mapMaybe id [selectedChoice, answerText]))
   in (questionRow, any (`elem` accepted) candidates)

findPlacementAnswer :: String -> [PlacementAnswer] -> Maybe PlacementAnswer
findPlacementAnswer requestedQuestionId =
  find (\PlacementAnswer {questionId} -> questionId == requestedQuestionId)

correctFor :: CefrLevel -> [(PlacementQuestionRow, Bool)] -> Int
correctFor level =
  length . filter (\(row, correct) -> correct && placementRowMatchesLevel level row)

totalFor :: CefrLevel -> [(PlacementQuestionRow, Bool)] -> Int
totalFor level =
  length . filter (\(row, _) -> placementRowMatchesLevel level row)

placementRowMatchesLevel :: CefrLevel -> PlacementQuestionRow -> Bool
placementRowMatchesLevel level PlacementQuestionRow {rowPlacementCefrBand} =
  cefrLevelForBand rowPlacementCefrBand == Just level

loadHighestPlacementLevel :: Connection -> Int -> IO (Maybe CefrLevel)
loadHighestPlacementLevel connection userIdValue = do
  rows <- query connection "SELECT placed_cefr_band FROM user_placement_results WHERE user_id = ?" (DbOnly userIdValue)
  let levels = mapMaybe (\PlacementResultRow {rowPlacementResultBand} -> cefrLevelForBand rowPlacementResultBand) rows
  pure
    ( case reverse (sortOn id levels) of
        level : _ -> Just level
        [] -> Nothing
    )

loadCompletedLessonCount :: Connection -> Int -> IO Int
loadCompletedLessonCount connection userIdValue = do
  values <- query connection "SELECT COUNT(*) FROM user_lesson_progress WHERE user_id = ? AND completed_at IS NOT NULL" (DbOnly userIdValue)
  pure (extractOnlyInt values)

markLessonsCompletedForPlacement :: Connection -> Int -> CefrLevel -> Int -> UTCTime -> IO ()
markLessonsCompletedForPlacement connection userIdValue placedLevel scorePercentValue now = do
  lessonRows <-
    query
      connection
      "SELECT l.lesson_id, u.cefr_band FROM lessons l JOIN units u ON u.unit_id = l.unit_id ORDER BY u.sort_index, l.sort_index"
      ()
  mapM_ markIfPrior lessonRows
  where
    markIfPrior LessonBandRow {rowBandLessonId, rowBandCefrBand}
      | shouldCompleteLessonForPlacement placedLevel rowBandCefrBand =
          execute
            connection
            "INSERT INTO user_lesson_progress (user_id, lesson_id, completed_at, best_accuracy, last_attempted_at, total_attempts) VALUES (?, ?, ?, ?, ?, 0) ON CONFLICT (user_id, lesson_id) DO UPDATE SET completed_at = COALESCE(user_lesson_progress.completed_at, excluded.completed_at), best_accuracy = CASE WHEN user_lesson_progress.best_accuracy > excluded.best_accuracy THEN user_lesson_progress.best_accuracy ELSE excluded.best_accuracy END, last_attempted_at = excluded.last_attempted_at"
            (userIdValue, rowBandLessonId, now, scorePercentValue, now)
      | otherwise = pure ()

buildVocabularyCard :: UTCTime -> [LexemeProgressRow] -> LexemeRow -> VocabularyCard
buildVocabularyCard now progressRows lexemeRow =
  let lexemeMastery = vocabularyLexemeMastery progressRows (rowLexemeId lexemeRow)
   in VocabularyCard
        { lexemeId = rowLexemeId lexemeRow,
          headword = rowLexemeHeadword lexemeRow,
          partOfSpeech = rowLexemePartOfSpeech lexemeRow,
          cefrBand = rowLexemeCefrBand lexemeRow,
          lessonId = rowLexemeLessonId lexemeRow,
          lessonTitle = rowLexemeLessonTitle lexemeRow,
          definition = rowLexemeDefinition lexemeRow,
          exampleSentence = rowLexemeExampleSentence lexemeRow,
          translation = rowLexemeTranslation lexemeRow,
          collocations = decodeList (rowLexemeCollocations lexemeRow),
          tags = decodeList (rowLexemeTags lexemeRow),
          masteryPercent = lexemeMastery,
          dueLabel = vocabularyLexemeDueLabel now progressRows (rowLexemeId lexemeRow)
        }

buildVocabularyReviewPrompts :: UTCTime -> [LexemeProgressRow] -> [LexemeRow] -> [VocabularyReviewPrompt]
buildVocabularyReviewPrompts now progressRows lexemeRows =
  map snd $
    sortOn fst $
      mapMaybe (buildVocabularyReviewCandidate now progressRows) lexemeRows

buildVocabularyReviewCandidate :: UTCTime -> [LexemeProgressRow] -> LexemeRow -> Maybe ((Int, Maybe UTCTime, Int, String), VocabularyReviewPrompt)
buildVocabularyReviewCandidate now progressRows lexemeRow =
  listToMaybe $
    sortOn fst $
      mapMaybe dimensionCandidate Vocabulary.vocabularyDimensions
  where
    dimensionCandidate dimension = do
      let maybeProgress = progressFor progressRows (rowLexemeId lexemeRow) dimension
          mastery = maybe 0 rowLexemeProgressMasteryPercent maybeProgress
          maybeDueAt = maybeProgress >>= rowLexemeProgressDueAt
      if mastery >= 100 || not (vocabularyReviewIsDue now maybeDueAt)
        then Nothing
        else
          Just
            ( ( vocabularyDueSortBucket maybeDueAt,
                maybeDueAt,
                mastery,
                Vocabulary.renderKnowledgeDimension dimension
              ),
              buildVocabularyReviewPrompt now maybeProgress lexemeRow dimension
            )

buildVocabularyReviewPrompt :: UTCTime -> Maybe LexemeProgressRow -> LexemeRow -> KnowledgeDimension -> VocabularyReviewPrompt
buildVocabularyReviewPrompt now maybeProgress lexemeRow dimension =
  let lexemeIdValue = rowLexemeId lexemeRow
      mastery = maybe 0 rowLexemeProgressMasteryPercent maybeProgress
      dueLabel = vocabularyDueLabel now mastery (maybeProgress >>= rowLexemeProgressDueAt)
      headwordValue = rowLexemeHeadword lexemeRow
      definitionValue = rowLexemeDefinition lexemeRow
      translationAnswers = maybe [] pure (rowLexemeTranslation lexemeRow)
      wordChoices = choicesForPrompt (Vocabulary.reviewIdFor lexemeIdValue dimension) headwordValue (decodeList (rowLexemeDistractors lexemeRow))
      collocationAnswers = decodeList (rowLexemeCollocations lexemeRow)
      collocationChoices = choicesForPrompt (Vocabulary.reviewIdFor lexemeIdValue dimension) (fromMaybe headwordValue (listToMaybe collocationAnswers)) (decodeList (rowLexemeConfusables lexemeRow))
      blankedExample = blankHeadword headwordValue (rowLexemeExampleSentence lexemeRow)
      promptFields =
        case dimension of
          Recognition ->
            ( "Which word matches this meaning?",
              Just definitionValue,
              wordChoices,
              Nothing,
              [headwordValue],
              Just ("It is a " <> rowLexemePartOfSpeech lexemeRow <> "."),
              "Recognition checks whether the meaning activates the right word."
            )
          MeaningRecall ->
            ( "Type a short meaning for this word.",
              Just (headwordValue <> " / " <> rowLexemeExampleSentence lexemeRow),
              [],
              Nothing,
              definitionValue : translationAnswers,
              Just "Use the English definition or the saved translation.",
              "Meaning recall checks whether the word can produce its meaning without choices."
            )
          FormRecall ->
            ( "Type the word that fits this clue.",
              Just definitionValue,
              [],
              Nothing,
              [headwordValue],
              Just blankedExample,
              "Form recall checks whether you can produce the written word."
            )
          UseInContext ->
            ( "Choose the word that fits the sentence.",
              Just blankedExample,
              wordChoices,
              Nothing,
              [headwordValue],
              Just definitionValue,
              "Context practice binds the word to a sentence, not just a gloss."
            )
          Collocation ->
            ( "Choose a natural phrase.",
              Just ("Target word: " <> headwordValue),
              if null collocationAnswers then wordChoices else collocationChoices,
              Nothing,
              if null collocationAnswers then [headwordValue] else collocationAnswers,
              Just "Useful words are easier to retrieve with their neighbors.",
              "Collocation practice stores the word with a phrase you can reuse."
            )
   in case promptFields of
        (promptText, promptDetailText, choiceValues, answerTextValue, acceptableAnswerValues, hintText, explanationText) ->
          VocabularyReviewPrompt
            { reviewId = Vocabulary.reviewIdFor lexemeIdValue dimension,
              lexemeId = lexemeIdValue,
              dimension = dimension,
              prompt = promptText,
              promptDetail = promptDetailText,
              choices = choiceValues,
              answerText = answerTextValue,
              acceptableAnswers = acceptableAnswerValues,
              hint = hintText,
              explanation = explanationText,
              masteryPercent = mastery,
              dueLabel = dueLabel
            }

choicesForPrompt :: String -> String -> [String] -> [String]
choicesForPrompt seed correctAnswer distractors =
  shuffleFragmentsWithSeed (ShuffleSeed seed) (nub (correctAnswer : distractors))

blankHeadword :: String -> String -> String
blankHeadword headwordValue exampleSentence =
  Text.unpack (Text.replace (Text.pack headwordValue) "____" (Text.pack exampleSentence))

vocabularyLexemeMastery :: [LexemeProgressRow] -> String -> Int
vocabularyLexemeMastery progressRows lexemeIdValue =
  percent
    (sum [vocabularyDimensionMastery progressRows lexemeIdValue dimension | dimension <- Vocabulary.vocabularyDimensions])
    (length Vocabulary.vocabularyDimensions)

vocabularyDimensionMastery :: [LexemeProgressRow] -> String -> KnowledgeDimension -> Int
vocabularyDimensionMastery progressRows lexemeIdValue dimension =
  maybe 0 rowLexemeProgressMasteryPercent (progressFor progressRows lexemeIdValue dimension)

vocabularyLexemeDueLabel :: UTCTime -> [LexemeProgressRow] -> String -> String
vocabularyLexemeDueLabel now progressRows lexemeIdValue =
  let relevantRows = filter (\row -> rowLexemeProgressLexemeId row == lexemeIdValue) progressRows
      missingDimensions = length relevantRows < length Vocabulary.vocabularyDimensions
      dueDates = mapMaybe rowLexemeProgressDueAt relevantRows
      dueNow = any (<= now) dueDates
      earliestFuture = listToMaybe (sortOn id (filter (> now) dueDates))
      mastery = vocabularyLexemeMastery progressRows lexemeIdValue
   in if mastery >= 100
        then "Mastered"
        else
          if missingDimensions
            then "New word"
            else
              if dueNow
                then "Due now"
                else maybe "New word" (renderDueLabel now) earliestFuture

vocabularyDueLabel :: UTCTime -> Int -> Maybe UTCTime -> String
vocabularyDueLabel now mastery maybeDueAt
  | mastery >= 100 = "Mastered"
  | otherwise =
      case maybeDueAt of
        Nothing -> "New word"
        Just dueAt -> renderDueLabel now dueAt

vocabularyReviewIsDue :: UTCTime -> Maybe UTCTime -> Bool
vocabularyReviewIsDue _ Nothing = True
vocabularyReviewIsDue now (Just dueAt) = dueAt <= now

vocabularyDueSortBucket :: Maybe UTCTime -> Int
vocabularyDueSortBucket Nothing = 0
vocabularyDueSortBucket (Just _) = 1

progressFor :: [LexemeProgressRow] -> String -> KnowledgeDimension -> Maybe LexemeProgressRow
progressFor progressRows lexemeIdValue dimension =
  find
    ( \LexemeProgressRow {rowLexemeProgressLexemeId, rowLexemeProgressDimension} ->
        rowLexemeProgressLexemeId == lexemeIdValue
          && rowLexemeProgressDimension == Vocabulary.renderKnowledgeDimension dimension
    )
    progressRows

vocabularyCardMastery :: VocabularyCard -> Int
vocabularyCardMastery VocabularyCard {masteryPercent} = masteryPercent

vocabularyPromptAcceptableAnswers :: VocabularyReviewPrompt -> [String]
vocabularyPromptAcceptableAnswers VocabularyReviewPrompt {acceptableAnswers} = acceptableAnswers

vocabularyPromptExplanation :: VocabularyReviewPrompt -> String
vocabularyPromptExplanation VocabularyReviewPrompt {explanation} = explanation

loadReviewSummaries :: Connection -> Int -> Int -> IO [ReviewSummary]
loadReviewSummaries connection userIdValue itemLimit = do
  reviewRows <-
    query
      connection
      "SELECT ep.exercise_id, e.lesson_id, l.title, e.prompt, ep.due_at, ep.mastery_percent FROM user_exercise_progress ep JOIN exercises e ON e.exercise_id = ep.exercise_id JOIN lessons l ON l.lesson_id = e.lesson_id WHERE ep.user_id = ? AND ep.due_at IS NOT NULL AND ep.mastery_percent < 100 ORDER BY ep.due_at ASC LIMIT ?"
      (userIdValue, itemLimit)
  now <- getCurrentTime
  pure
    ( map
        (\ReviewRow {rowReviewExerciseId, rowReviewLessonId, rowReviewLessonTitle, rowReviewPrompt, rowReviewDueAt, rowReviewMasteryPercent} ->
           ReviewSummary
             { exerciseId = rowReviewExerciseId,
               lessonId = rowReviewLessonId,
               lessonTitle = rowReviewLessonTitle,
               prompt = rowReviewPrompt,
               dueLabel = renderDueLabel now rowReviewDueAt,
               masteryPercent = rowReviewMasteryPercent
             }
        )
        reviewRows
    )

loadDueReviewCount :: Connection -> Int -> IO Int
loadDueReviewCount connection userIdValue = do
  now <- getCurrentTime
  counts <- query connection "SELECT COUNT(*) FROM user_exercise_progress WHERE user_id = ? AND due_at IS NOT NULL AND due_at <= ? AND mastery_percent < 100" (userIdValue, now)
  pure (extractOnlyInt counts)

loadAccuracyPercent :: Connection -> Int -> IO Int
loadAccuracyPercent connection userIdValue = do
  values <-
    query
      connection
      "SELECT COALESCE(CAST(ROUND(100.0 * SUM(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0)) AS INTEGER), 0) FROM user_attempt_answers WHERE user_id = ?"
      (DbOnly userIdValue)
  pure (extractOnlyInt values)

loadProfileRow :: Connection -> Int -> IO ProfileRow
loadProfileRow connection userIdValue = do
  rows <-
    query
      connection
      "SELECT u.display_name, COALESCE(p.xp, 0), COALESCE(p.streak_days, 0), p.last_active_day FROM users u LEFT JOIN user_profiles p ON p.user_id = u.user_id WHERE u.user_id = ?"
      (DbOnly userIdValue)
  case rows of
    profileRow : _ -> pure profileRow
    [] -> pure (ProfileRow "Learner" 0 0 Nothing)

extractOnlyInt :: [DbOnly Int] -> Int
extractOnlyInt rows =
  case rows of
    DbOnly value : _ -> value
    [] -> 0

loadOpenAttemptForLesson :: Connection -> Int -> String -> IO (Maybe AttemptRow)
loadOpenAttemptForLesson connection userIdValue lessonIdValue = do
  rows <-
    query
      connection
      "SELECT attempt_id, lesson_id, total_exercises, answered_count, correct_count, finished, xp_awarded, completed_at, lesson_completed, presentation_seed FROM user_attempts WHERE user_id = ? AND lesson_id = ? AND finished = 0 ORDER BY attempt_id DESC LIMIT 1"
      (userIdValue, lessonIdValue)
  pure (listToMaybe rows)

loadAttemptById :: Connection -> Int -> Int -> IO (Maybe AttemptRow)
loadAttemptById connection userIdValue attemptIdValue = do
  rows <-
    query
      connection
      "SELECT attempt_id, lesson_id, total_exercises, answered_count, correct_count, finished, xp_awarded, completed_at, lesson_completed, presentation_seed FROM user_attempts WHERE user_id = ? AND attempt_id = ?"
      (userIdValue, attemptIdValue)
  pure (listToMaybe rows)

loadExerciseProgress :: Connection -> Int -> String -> IO (Maybe ExerciseProgressRow)
loadExerciseProgress connection userIdValue exerciseIdValue = do
  rows <-
    query
      connection
      "SELECT correct_count, incorrect_count, mastery_percent FROM user_exercise_progress WHERE user_id = ? AND exercise_id = ?"
      (userIdValue, exerciseIdValue)
  pure (listToMaybe rows)

loadLessonProgress :: Connection -> Int -> String -> IO (Maybe LessonProgressRow)
loadLessonProgress connection userIdValue lessonIdValue = do
  rows <-
    query
      connection
      "SELECT completed_at, best_accuracy FROM user_lesson_progress WHERE user_id = ? AND lesson_id = ?"
      (userIdValue, lessonIdValue)
  pure (listToMaybe rows)

loadLessonMeta :: Connection -> String -> IO (Maybe LessonMetaRow)
loadLessonMeta connection lessonIdValue = do
  rows <- query connection "SELECT xp_reward FROM lessons WHERE lesson_id = ?" (DbOnly lessonIdValue)
  pure (listToMaybe rows)

applyCompletionRewards :: Connection -> Int -> Int -> UTCTime -> IO ()
applyCompletionRewards connection userIdValue xpAwardedValue now = do
  profileRow <- loadProfileRow connection userIdValue
  let today = utctDay now
      newStreak = advanceStreak today (rowLearnerStreak profileRow) (rowLearnerLastActiveDay profileRow)
      nextXp = rowLearnerXp profileRow + xpAwardedValue
  execute
    connection
    "INSERT INTO user_profiles (user_id, xp, streak_days, last_active_day) VALUES (?, ?, ?, ?) ON CONFLICT (user_id) DO UPDATE SET xp = excluded.xp, streak_days = excluded.streak_days, last_active_day = excluded.last_active_day"
    (userIdValue, nextXp, newStreak, Just (formatDay today))

hoursToDiff :: Int -> NominalDiffTime
hoursToDiff hours = fromIntegral (hours * 3600)

boolToInt :: Bool -> Int
boolToInt True = 1
boolToInt False = 0

parseAttemptIdentifier :: String -> Either ServiceError Int
parseAttemptIdentifier attemptIdText =
  case readMaybe attemptIdText of
    Just attemptIdValue -> Right attemptIdValue
    Nothing -> Left (ValidationError ("Attempt id is not a valid integer: " <> attemptIdText))

generatePresentationSeed :: IO String
generatePresentationSeed = toHex <$> Entropy.getEntropy 16

nonEmptyPresentationSeed :: Int -> String -> String
nonEmptyPresentationSeed attemptIdValue presentationSeed
  | null presentationSeed = show attemptIdValue
  | otherwise = presentationSeed

toHex :: BS.ByteString -> String
toHex =
  BS8.unpack . BS.concatMap encodeByte
  where
    hexChars = "0123456789abcdef"
    hexChar index = BS8.index hexChars index
    encodeByte byte =
      BS8.pack
        [ hexChar (fromIntegral byte `div` 16),
          hexChar (fromIntegral byte `mod` 16)
        ]

unitCompletedLessons :: UnitSummary -> Int
unitCompletedLessons UnitSummary {completedLessons} = completedLessons

unitTotalLessons :: UnitSummary -> Int
unitTotalLessons UnitSummary {totalLessons} = totalLessons

unitTitle :: UnitSummary -> String
unitTitle UnitSummary {title} = title

unitLessonSummaries :: UnitSummary -> [LessonSummary]
unitLessonSummaries UnitSummary {lessonSummaries} = lessonSummaries

lessonSummaryId :: LessonSummary -> String
lessonSummaryId LessonSummary {lessonId} = lessonId

lessonSummaryStatus :: LessonSummary -> LessonStatus
lessonSummaryStatus LessonSummary {status} = status

exercisePromptId :: ExercisePrompt -> String
exercisePromptId ExercisePrompt {exerciseId} = exerciseId

exercisePromptExplanation :: ExercisePrompt -> String
exercisePromptExplanation ExercisePrompt {explanation} = explanation

answerSubmissionExerciseId :: AnswerSubmission -> String
answerSubmissionExerciseId AnswerSubmission {exerciseId} = exerciseId

bootstrapProfile :: AppBootstrap -> LearnerProfile
bootstrapProfile AppBootstrap {profile} = profile

bootstrapStats :: AppBootstrap -> DashboardStats
bootstrapStats AppBootstrap {stats} = stats

bootstrapRecommendedLessonId :: AppBootstrap -> Maybe String
bootstrapRecommendedLessonId AppBootstrap {recommendedLessonId} = recommendedLessonId

bootstrapVocabulary :: AppBootstrap -> VocabularyDashboard
bootstrapVocabulary AppBootstrap {vocabulary} = vocabulary
