{-# LANGUAGE CPP #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}

module ReactiveEnglish.Database
  ( prepareDatabase,
  )
where

import Control.Exception (IOException, catch)
import Control.Monad (forM_, unless, when)
import Data.Aeson (eitherDecodeStrict')
import qualified Data.Aeson as Aeson
import Data.Bits (xor)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BL
import Data.Foldable (traverse_)
import Data.Maybe (fromMaybe)
import Data.Time.Clock (getCurrentTime)
import Data.Word (Word64)
#ifdef POSTGRES_BACKEND
import qualified Database.PostgreSQL.Simple.ToField as PGToField
import qualified Database.PostgreSQL.Simple.ToRow as PGToRow
#endif
import qualified Database.SQLite.Simple.ToField as SQLiteToField
import qualified Database.SQLite.Simple.ToRow as SQLiteToRow
import ReactiveEnglish.Curriculum
  ( Curriculum (units),
    CurriculumExercise (..),
    CurriculumLexeme (..),
    CurriculumLesson (..),
    CurriculumUnit (..),
    lexemes,
  )
import ReactiveEnglish.Db
  ( DbConnection,
    DbDialect (..),
    DbOnly (..),
    dbDialect,
    execute,
    execute_,
    query_,
    withTransaction,
  )
import ReactiveEnglish.Schema.Generated (ExerciseKind (..))

data ExerciseSeedRow = ExerciseSeedRow
  { seedExerciseId :: String,
    seedLessonId :: String,
    seedSortIndex :: Int,
    seedKind :: String,
    seedPrompt :: String,
    seedPromptDetail :: Maybe String,
    seedChoicesJson :: BS.ByteString,
    seedFragmentsJson :: BS.ByteString,
    seedAnswerText :: Maybe String,
    seedAcceptableAnswersJson :: BS.ByteString,
    seedTranslation :: Maybe String,
    seedHint :: Maybe String,
    seedExplanation :: String
  }

instance SQLiteToRow.ToRow ExerciseSeedRow where
  toRow ExerciseSeedRow {seedExerciseId, seedLessonId, seedSortIndex, seedKind, seedPrompt, seedPromptDetail, seedChoicesJson, seedFragmentsJson, seedAnswerText, seedAcceptableAnswersJson, seedTranslation, seedHint, seedExplanation} =
    [ SQLiteToField.toField seedExerciseId,
      SQLiteToField.toField seedLessonId,
      SQLiteToField.toField seedSortIndex,
      SQLiteToField.toField seedKind,
      SQLiteToField.toField seedPrompt,
      SQLiteToField.toField seedPromptDetail,
      SQLiteToField.toField seedChoicesJson,
      SQLiteToField.toField seedFragmentsJson,
      SQLiteToField.toField seedAnswerText,
      SQLiteToField.toField seedAcceptableAnswersJson,
      SQLiteToField.toField seedTranslation,
      SQLiteToField.toField seedHint,
      SQLiteToField.toField seedExplanation
    ]

#ifdef POSTGRES_BACKEND
instance PGToRow.ToRow ExerciseSeedRow where
  toRow ExerciseSeedRow {seedExerciseId, seedLessonId, seedSortIndex, seedKind, seedPrompt, seedPromptDetail, seedChoicesJson, seedFragmentsJson, seedAnswerText, seedAcceptableAnswersJson, seedTranslation, seedHint, seedExplanation} =
    [ PGToField.toField seedExerciseId,
      PGToField.toField seedLessonId,
      PGToField.toField seedSortIndex,
      PGToField.toField seedKind,
      PGToField.toField seedPrompt,
      PGToField.toField seedPromptDetail,
      PGToField.toField seedChoicesJson,
      PGToField.toField seedFragmentsJson,
      PGToField.toField seedAnswerText,
      PGToField.toField seedAcceptableAnswersJson,
      PGToField.toField seedTranslation,
      PGToField.toField seedHint,
      PGToField.toField seedExplanation
    ]
#endif

data LexemeSeedRow = LexemeSeedRow
  { seedLexemeId :: String,
    seedLexemeLessonId :: String,
    seedHeadword :: String,
    seedPartOfSpeech :: String,
    seedCefrBand :: String,
    seedDefinition :: String,
    seedExampleSentence :: String,
    seedLexemeTranslation :: Maybe String,
    seedCollocationsJson :: BS.ByteString,
    seedDistractorsJson :: BS.ByteString,
    seedConfusablesJson :: BS.ByteString,
    seedTagsJson :: BS.ByteString
  }

instance SQLiteToRow.ToRow LexemeSeedRow where
  toRow LexemeSeedRow {seedLexemeId, seedLexemeLessonId, seedHeadword, seedPartOfSpeech, seedCefrBand, seedDefinition, seedExampleSentence, seedLexemeTranslation, seedCollocationsJson, seedDistractorsJson, seedConfusablesJson, seedTagsJson} =
    [ SQLiteToField.toField seedLexemeId,
      SQLiteToField.toField seedLexemeLessonId,
      SQLiteToField.toField seedHeadword,
      SQLiteToField.toField seedPartOfSpeech,
      SQLiteToField.toField seedCefrBand,
      SQLiteToField.toField seedDefinition,
      SQLiteToField.toField seedExampleSentence,
      SQLiteToField.toField seedLexemeTranslation,
      SQLiteToField.toField seedCollocationsJson,
      SQLiteToField.toField seedDistractorsJson,
      SQLiteToField.toField seedConfusablesJson,
      SQLiteToField.toField seedTagsJson
    ]

#ifdef POSTGRES_BACKEND
instance PGToRow.ToRow LexemeSeedRow where
  toRow LexemeSeedRow {seedLexemeId, seedLexemeLessonId, seedHeadword, seedPartOfSpeech, seedCefrBand, seedDefinition, seedExampleSentence, seedLexemeTranslation, seedCollocationsJson, seedDistractorsJson, seedConfusablesJson, seedTagsJson} =
    [ PGToField.toField seedLexemeId,
      PGToField.toField seedLexemeLessonId,
      PGToField.toField seedHeadword,
      PGToField.toField seedPartOfSpeech,
      PGToField.toField seedCefrBand,
      PGToField.toField seedDefinition,
      PGToField.toField seedExampleSentence,
      PGToField.toField seedLexemeTranslation,
      PGToField.toField seedCollocationsJson,
      PGToField.toField seedDistractorsJson,
      PGToField.toField seedConfusablesJson,
      PGToField.toField seedTagsJson
    ]
#endif

prepareDatabase :: DbConnection -> FilePath -> IO ()
prepareDatabase connection curriculumPath = do
  case dbDialect connection of
    SQLiteDialect -> execute_ connection "PRAGMA foreign_keys = ON"
    PostgresDialect -> pure ()
  runMigrations connection
  curriculumBytes <-
    BS.readFile curriculumPath
      `catch` \readFailure ->
        Prelude.ioError
          ( userError
              ( "Unable to read curriculum file at "
                  <> curriculumPath
                  <> ": "
                  <> show (readFailure :: IOException)
              )
          )
  curriculum <-
    case eitherDecodeStrict' curriculumBytes of
      Left message ->
        Prelude.ioError
          ( userError
              ( "Unable to decode curriculum JSON at "
                  <> curriculumPath
                  <> ": "
                  <> message
              )
          )
      Right decoded -> pure decoded

  shouldReseed <- needsReseed connection (curriculumFingerprint curriculumBytes)
  when shouldReseed $
    seedCurriculum connection curriculum (curriculumFingerprint curriculumBytes)

runMigrations :: DbConnection -> IO ()
runMigrations connection = do
  execute_
    connection
    ("CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY, applied_at " <> timestampType (dbDialect connection) <> " NOT NULL)")
  appliedVersions <- map (\(DbOnly version) -> version) <$> query_ connection "SELECT version FROM schema_migrations"
  traverse_ (applyMigration connection appliedVersions) (migrations (dbDialect connection))

applyMigration :: DbConnection -> [Int] -> (Int, [String]) -> IO ()
applyMigration connection appliedVersions (version, statements) =
  unless (version `elem` appliedVersions) $
    withTransaction connection $ do
      traverse_ (execute_ connection) statements
      appliedAt <- getCurrentTime
      execute connection "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)" (version, appliedAt)

migrations :: DbDialect -> [(Int, [String])]
migrations dialect =
  [ ( 1,
      [ "CREATE TABLE IF NOT EXISTS curriculum_meta (singleton_id INTEGER PRIMARY KEY CHECK (singleton_id = 1), curriculum_fingerprint TEXT NOT NULL, seeded_at " <> timestampType dialect <> " NOT NULL)",
        "CREATE TABLE IF NOT EXISTS units (unit_id TEXT PRIMARY KEY, sort_index INTEGER NOT NULL, title TEXT NOT NULL, cefr_band TEXT NOT NULL, focus TEXT NOT NULL)",
        "CREATE TABLE IF NOT EXISTS lessons (lesson_id TEXT PRIMARY KEY, unit_id TEXT NOT NULL REFERENCES units(unit_id) ON DELETE CASCADE, sort_index INTEGER NOT NULL, title TEXT NOT NULL, subtitle TEXT NOT NULL, goal TEXT NOT NULL, xp_reward INTEGER NOT NULL, narrative TEXT NOT NULL)",
        "CREATE TABLE IF NOT EXISTS lesson_tips (lesson_id TEXT NOT NULL REFERENCES lessons(lesson_id) ON DELETE CASCADE, sort_index INTEGER NOT NULL, tip TEXT NOT NULL, PRIMARY KEY (lesson_id, sort_index))",
        "CREATE TABLE IF NOT EXISTS exercises (exercise_id TEXT PRIMARY KEY, lesson_id TEXT NOT NULL REFERENCES lessons(lesson_id) ON DELETE CASCADE, sort_index INTEGER NOT NULL, kind TEXT NOT NULL, prompt TEXT NOT NULL, prompt_detail TEXT, choices_json " <> binaryType dialect <> " NOT NULL, fragments_json " <> binaryType dialect <> " NOT NULL, answer_text TEXT, acceptable_answers_json " <> binaryType dialect <> " NOT NULL, translation TEXT, hint TEXT, explanation TEXT NOT NULL)",
        "CREATE TABLE IF NOT EXISTS learner_profile (learner_id INTEGER PRIMARY KEY CHECK (learner_id = 1), learner_name TEXT NOT NULL, xp INTEGER NOT NULL DEFAULT 0, streak_days INTEGER NOT NULL DEFAULT 0, last_active_day TEXT)",
        "CREATE TABLE IF NOT EXISTS lesson_progress (lesson_id TEXT PRIMARY KEY REFERENCES lessons(lesson_id) ON DELETE CASCADE, completed_at " <> timestampType dialect <> ", best_accuracy INTEGER NOT NULL DEFAULT 0, last_attempted_at " <> timestampType dialect <> ", total_attempts INTEGER NOT NULL DEFAULT 0)",
        "CREATE TABLE IF NOT EXISTS exercise_progress (exercise_id TEXT PRIMARY KEY REFERENCES exercises(exercise_id) ON DELETE CASCADE, correct_count INTEGER NOT NULL DEFAULT 0, incorrect_count INTEGER NOT NULL DEFAULT 0, mastery_percent INTEGER NOT NULL DEFAULT 0, due_at " <> timestampType dialect <> ", last_answered_at " <> timestampType dialect <> ")",
        "CREATE TABLE IF NOT EXISTS attempts (attempt_id " <> identityPrimaryKey dialect <> ", lesson_id TEXT NOT NULL REFERENCES lessons(lesson_id) ON DELETE CASCADE, started_at " <> timestampType dialect <> " NOT NULL, completed_at " <> timestampType dialect <> ", total_exercises INTEGER NOT NULL, answered_count INTEGER NOT NULL DEFAULT 0, correct_count INTEGER NOT NULL DEFAULT 0, finished INTEGER NOT NULL DEFAULT 0, xp_awarded INTEGER NOT NULL DEFAULT 0, lesson_completed INTEGER NOT NULL DEFAULT 0)",
        "CREATE TABLE IF NOT EXISTS attempt_answers (answer_id " <> identityPrimaryKey dialect <> ", attempt_id INTEGER NOT NULL REFERENCES attempts(attempt_id) ON DELETE CASCADE, exercise_id TEXT NOT NULL REFERENCES exercises(exercise_id) ON DELETE CASCADE, submitted_answer TEXT NOT NULL, is_correct INTEGER NOT NULL, submitted_at " <> timestampType dialect <> " NOT NULL, UNIQUE (attempt_id, exercise_id))"
      ]
    ),
    ( 2,
      [ "CREATE INDEX IF NOT EXISTS idx_lessons_unit_order ON lessons(unit_id, sort_index)",
        "CREATE INDEX IF NOT EXISTS idx_exercises_lesson_order ON exercises(lesson_id, sort_index)",
        "CREATE INDEX IF NOT EXISTS idx_attempts_lesson_finished ON attempts(lesson_id, finished)",
        "CREATE INDEX IF NOT EXISTS idx_review_due ON exercise_progress(due_at)"
      ]
    ),
    ( 3,
      [ "CREATE TABLE IF NOT EXISTS users (user_id " <> identityPrimaryKey dialect <> ", display_name TEXT NOT NULL, email TEXT NOT NULL UNIQUE, avatar_url TEXT, created_at " <> timestampType dialect <> " NOT NULL, updated_at " <> timestampType dialect <> " NOT NULL, last_login_at " <> timestampType dialect <> " NOT NULL)",
        "CREATE TABLE IF NOT EXISTS auth_identities (provider TEXT NOT NULL, provider_user_id TEXT NOT NULL, user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE, email TEXT NOT NULL, display_name TEXT NOT NULL, avatar_url TEXT, created_at " <> timestampType dialect <> " NOT NULL, updated_at " <> timestampType dialect <> " NOT NULL, PRIMARY KEY (provider, provider_user_id))",
        "CREATE TABLE IF NOT EXISTS sessions (session_id TEXT PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE, provider TEXT NOT NULL, created_at " <> timestampType dialect <> " NOT NULL, expires_at " <> timestampType dialect <> " NOT NULL, last_seen_at " <> timestampType dialect <> " NOT NULL)",
        "CREATE TABLE IF NOT EXISTS user_profiles (user_id INTEGER PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE, xp INTEGER NOT NULL DEFAULT 0, streak_days INTEGER NOT NULL DEFAULT 0, last_active_day TEXT)",
        "CREATE TABLE IF NOT EXISTS user_lesson_progress (user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE, lesson_id TEXT NOT NULL REFERENCES lessons(lesson_id) ON DELETE CASCADE, completed_at " <> timestampType dialect <> ", best_accuracy INTEGER NOT NULL DEFAULT 0, last_attempted_at " <> timestampType dialect <> ", total_attempts INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (user_id, lesson_id))",
        "CREATE TABLE IF NOT EXISTS user_exercise_progress (user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE, exercise_id TEXT NOT NULL REFERENCES exercises(exercise_id) ON DELETE CASCADE, correct_count INTEGER NOT NULL DEFAULT 0, incorrect_count INTEGER NOT NULL DEFAULT 0, mastery_percent INTEGER NOT NULL DEFAULT 0, due_at " <> timestampType dialect <> ", last_answered_at " <> timestampType dialect <> ", PRIMARY KEY (user_id, exercise_id))",
        "CREATE TABLE IF NOT EXISTS user_attempts (attempt_id " <> identityPrimaryKey dialect <> ", user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE, lesson_id TEXT NOT NULL REFERENCES lessons(lesson_id) ON DELETE CASCADE, started_at " <> timestampType dialect <> " NOT NULL, completed_at " <> timestampType dialect <> ", total_exercises INTEGER NOT NULL, answered_count INTEGER NOT NULL DEFAULT 0, correct_count INTEGER NOT NULL DEFAULT 0, finished INTEGER NOT NULL DEFAULT 0, xp_awarded INTEGER NOT NULL DEFAULT 0, lesson_completed INTEGER NOT NULL DEFAULT 0)",
        "CREATE TABLE IF NOT EXISTS user_attempt_answers (answer_id " <> identityPrimaryKey dialect <> ", user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE, attempt_id INTEGER NOT NULL REFERENCES user_attempts(attempt_id) ON DELETE CASCADE, exercise_id TEXT NOT NULL REFERENCES exercises(exercise_id) ON DELETE CASCADE, submitted_answer TEXT NOT NULL, is_correct INTEGER NOT NULL, submitted_at " <> timestampType dialect <> " NOT NULL, UNIQUE (attempt_id, exercise_id))",
        "CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id)",
        "CREATE INDEX IF NOT EXISTS idx_sessions_expiry ON sessions(expires_at)",
        "CREATE INDEX IF NOT EXISTS idx_auth_identities_user ON auth_identities(user_id)",
        "CREATE INDEX IF NOT EXISTS idx_user_lesson_progress_user ON user_lesson_progress(user_id, lesson_id)",
        "CREATE INDEX IF NOT EXISTS idx_user_exercise_review_due ON user_exercise_progress(user_id, due_at)",
        "CREATE INDEX IF NOT EXISTS idx_user_attempts_lesson_finished ON user_attempts(user_id, lesson_id, finished)",
        "CREATE INDEX IF NOT EXISTS idx_user_attempt_answers_user ON user_attempt_answers(user_id, attempt_id)"
      ]
    ),
    ( 4,
      [ "ALTER TABLE attempts ADD COLUMN presentation_seed TEXT NOT NULL DEFAULT ''",
        "ALTER TABLE user_attempts ADD COLUMN presentation_seed TEXT NOT NULL DEFAULT ''"
      ]
    ),
    ( 5,
      [ "CREATE TABLE IF NOT EXISTS lexemes (lexeme_id TEXT PRIMARY KEY, lesson_id TEXT NOT NULL REFERENCES lessons(lesson_id) ON DELETE CASCADE, headword TEXT NOT NULL, part_of_speech TEXT NOT NULL, cefr_band TEXT NOT NULL, definition TEXT NOT NULL, example_sentence TEXT NOT NULL, translation TEXT, collocations_json " <> binaryType dialect <> " NOT NULL, distractors_json " <> binaryType dialect <> " NOT NULL, confusables_json " <> binaryType dialect <> " NOT NULL, tags_json " <> binaryType dialect <> " NOT NULL)",
        "CREATE TABLE IF NOT EXISTS user_lexeme_progress (user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE, lexeme_id TEXT NOT NULL REFERENCES lexemes(lexeme_id) ON DELETE CASCADE, dimension TEXT NOT NULL, correct_count INTEGER NOT NULL DEFAULT 0, incorrect_count INTEGER NOT NULL DEFAULT 0, mastery_percent INTEGER NOT NULL DEFAULT 0, due_at " <> timestampType dialect <> ", last_reviewed_at " <> timestampType dialect <> ", PRIMARY KEY (user_id, lexeme_id, dimension))",
        "CREATE TABLE IF NOT EXISTS user_lexeme_review_events (event_id " <> identityPrimaryKey dialect <> ", user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE, lexeme_id TEXT NOT NULL REFERENCES lexemes(lexeme_id) ON DELETE CASCADE, dimension TEXT NOT NULL, submitted_answer TEXT NOT NULL, is_correct INTEGER NOT NULL, mastery_percent INTEGER NOT NULL, xp_delta INTEGER NOT NULL, reviewed_at " <> timestampType dialect <> " NOT NULL)",
        "CREATE INDEX IF NOT EXISTS idx_lexemes_lesson ON lexemes(lesson_id)",
        "CREATE INDEX IF NOT EXISTS idx_user_lexeme_due ON user_lexeme_progress(user_id, due_at, mastery_percent)",
        "CREATE INDEX IF NOT EXISTS idx_user_lexeme_events_user ON user_lexeme_review_events(user_id, reviewed_at)"
      ]
    )
  ]

identityPrimaryKey :: DbDialect -> String
identityPrimaryKey dialect =
  case dialect of
    SQLiteDialect -> "INTEGER PRIMARY KEY AUTOINCREMENT"
    PostgresDialect -> "INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY"

binaryType :: DbDialect -> String
binaryType dialect =
  case dialect of
    SQLiteDialect -> "BLOB"
    PostgresDialect -> "BYTEA"

timestampType :: DbDialect -> String
timestampType dialect =
  case dialect of
    SQLiteDialect -> "TEXT"
    PostgresDialect -> "TIMESTAMPTZ"

needsReseed :: DbConnection -> String -> IO Bool
needsReseed connection fingerprint = do
  stored <- query_ connection "SELECT curriculum_fingerprint FROM curriculum_meta WHERE singleton_id = 1" :: IO [DbOnly String]
  unitCount <- query_ connection "SELECT COUNT(*) FROM units" :: IO [DbOnly Int]
  pure $
    case (stored, unitCount) of
      ([DbOnly existingFingerprint], [DbOnly count]) -> existingFingerprint /= fingerprint || count == 0
      _ -> True

seedCurriculum :: DbConnection -> Curriculum -> String -> IO ()
seedCurriculum connection curriculum fingerprint =
  withTransaction connection $ do
    execute_ connection "DELETE FROM attempts WHERE finished = 0"
    execute_ connection "DELETE FROM user_attempts WHERE finished = 0"
    upsertUnits connection (units curriculum)
    upsertLessons connection (units curriculum)
    upsertExercises connection (units curriculum)
    upsertLexemes connection (fromMaybe [] (lexemes curriculum))
    pruneRemovedRows connection curriculum
    seededAt <- getCurrentTime
    execute
      connection
      "INSERT INTO curriculum_meta (singleton_id, curriculum_fingerprint, seeded_at) VALUES (1, ?, ?) ON CONFLICT (singleton_id) DO UPDATE SET curriculum_fingerprint = excluded.curriculum_fingerprint, seeded_at = excluded.seeded_at"
      (fingerprint, seededAt)

upsertUnits :: DbConnection -> [CurriculumUnit] -> IO ()
upsertUnits connection curriculumUnits =
  forM_ curriculumUnits $ \curriculumUnit ->
    execute
      connection
      "INSERT INTO units (unit_id, sort_index, title, cefr_band, focus) VALUES (?, ?, ?, ?, ?) ON CONFLICT (unit_id) DO UPDATE SET sort_index = excluded.sort_index, title = excluded.title, cefr_band = excluded.cefr_band, focus = excluded.focus"
      (unitId curriculumUnit, curriculumUnitIndex curriculumUnit, curriculumUnitTitle curriculumUnit, cefrBand curriculumUnit, focus curriculumUnit)

upsertLessons :: DbConnection -> [CurriculumUnit] -> IO ()
upsertLessons connection curriculumUnits =
  forM_ curriculumUnits $ \curriculumUnit ->
    forM_ (lessons curriculumUnit) $ \curriculumLesson -> do
      execute
        connection
        "INSERT INTO lessons (lesson_id, unit_id, sort_index, title, subtitle, goal, xp_reward, narrative) VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT (lesson_id) DO UPDATE SET unit_id = excluded.unit_id, sort_index = excluded.sort_index, title = excluded.title, subtitle = excluded.subtitle, goal = excluded.goal, xp_reward = excluded.xp_reward, narrative = excluded.narrative"
        ( lessonId curriculumLesson,
          unitId curriculumUnit,
          curriculumLessonIndex curriculumLesson,
          curriculumLessonTitle curriculumLesson,
          subtitle curriculumLesson,
          goal curriculumLesson,
          xpReward curriculumLesson,
          narrative curriculumLesson
        )
      execute connection "DELETE FROM lesson_tips WHERE lesson_id = ?" (DbOnly (lessonId curriculumLesson))
      forM_ (zip [(1 :: Int) ..] (tips curriculumLesson)) $ \(tipIndex, tipText) ->
        execute
          connection
          "INSERT INTO lesson_tips (lesson_id, sort_index, tip) VALUES (?, ?, ?)"
          (lessonId curriculumLesson, tipIndex, tipText)

upsertExercises :: DbConnection -> [CurriculumUnit] -> IO ()
upsertExercises connection curriculumUnits =
  forM_ curriculumUnits $ \curriculumUnit ->
    forM_ (lessons curriculumUnit) $ \curriculumLesson ->
      forM_ (zip [(1 :: Int) ..] (exercises curriculumLesson)) $ \(exerciseIndex, curriculumExercise) ->
        execute
          connection
          "INSERT INTO exercises (exercise_id, lesson_id, sort_index, kind, prompt, prompt_detail, choices_json, fragments_json, answer_text, acceptable_answers_json, translation, hint, explanation) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT (exercise_id) DO UPDATE SET lesson_id = excluded.lesson_id, sort_index = excluded.sort_index, kind = excluded.kind, prompt = excluded.prompt, prompt_detail = excluded.prompt_detail, choices_json = excluded.choices_json, fragments_json = excluded.fragments_json, answer_text = excluded.answer_text, acceptable_answers_json = excluded.acceptable_answers_json, translation = excluded.translation, hint = excluded.hint, explanation = excluded.explanation"
          ExerciseSeedRow
            { seedExerciseId = exerciseId curriculumExercise,
              seedLessonId = lessonId curriculumLesson,
              seedSortIndex = exerciseIndex,
              seedKind = renderExerciseKind (kind curriculumExercise),
              seedPrompt = prompt curriculumExercise,
              seedPromptDetail = promptDetail curriculumExercise,
              seedChoicesJson = BL.toStrict (Aeson.encode (choices curriculumExercise)),
              seedFragmentsJson = BL.toStrict (Aeson.encode (fragments curriculumExercise)),
              seedAnswerText = answerText curriculumExercise,
              seedAcceptableAnswersJson = BL.toStrict (Aeson.encode (acceptableAnswers curriculumExercise)),
              seedTranslation = translation curriculumExercise,
              seedHint = hint curriculumExercise,
              seedExplanation = explanation curriculumExercise
            }

upsertLexemes :: DbConnection -> [CurriculumLexeme] -> IO ()
upsertLexemes connection curriculumLexemes =
  forM_ curriculumLexemes $ \curriculumLexeme ->
    execute
      connection
      "INSERT INTO lexemes (lexeme_id, lesson_id, headword, part_of_speech, cefr_band, definition, example_sentence, translation, collocations_json, distractors_json, confusables_json, tags_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT (lexeme_id) DO UPDATE SET lesson_id = excluded.lesson_id, headword = excluded.headword, part_of_speech = excluded.part_of_speech, cefr_band = excluded.cefr_band, definition = excluded.definition, example_sentence = excluded.example_sentence, translation = excluded.translation, collocations_json = excluded.collocations_json, distractors_json = excluded.distractors_json, confusables_json = excluded.confusables_json, tags_json = excluded.tags_json"
      LexemeSeedRow
        { seedLexemeId = lexemeId curriculumLexeme,
          seedLexemeLessonId = lexemeLessonId curriculumLexeme,
          seedHeadword = headword curriculumLexeme,
          seedPartOfSpeech = partOfSpeech curriculumLexeme,
          seedCefrBand = lexemeCefrBand curriculumLexeme,
          seedDefinition = definition curriculumLexeme,
          seedExampleSentence = exampleSentence curriculumLexeme,
          seedLexemeTranslation = lexemeTranslation curriculumLexeme,
          seedCollocationsJson = BL.toStrict (Aeson.encode (collocations curriculumLexeme)),
          seedDistractorsJson = BL.toStrict (Aeson.encode (distractors curriculumLexeme)),
          seedConfusablesJson = BL.toStrict (Aeson.encode (confusables curriculumLexeme)),
          seedTagsJson = BL.toStrict (Aeson.encode (tags curriculumLexeme))
        }

pruneRemovedRows :: DbConnection -> Curriculum -> IO ()
pruneRemovedRows connection curriculum = do
  let curriculumUnits = units curriculum
  let activeUnitIds = map unitId curriculumUnits
      activeLessons = [lessonId curriculumLesson | curriculumUnit <- curriculumUnits, curriculumLesson <- lessons curriculumUnit]
      activeExercises =
        [ exerciseId curriculumExercise
          | curriculumUnit <- curriculumUnits,
            curriculumLesson <- lessons curriculumUnit,
            curriculumExercise <- exercises curriculumLesson
        ]
      activeLexemes = map lexemeId (fromMaybe [] (lexemes curriculum))
  deleteMissingIds connection "lexemes" "lexeme_id" activeLexemes
  deleteMissingIds connection "exercises" "exercise_id" activeExercises
  deleteMissingIds connection "lessons" "lesson_id" activeLessons
  deleteMissingIds connection "units" "unit_id" activeUnitIds

deleteMissingIds :: DbConnection -> String -> String -> [String] -> IO ()
deleteMissingIds connection tableName columnName activeIds = do
  existingIdRows <- query_ connection ("SELECT " <> columnName <> " FROM " <> tableName) :: IO [DbOnly String]
  let existingIds = map (\(DbOnly identifier) -> identifier) existingIdRows
  forM_ existingIds $ \existingId ->
    when (existingId `notElem` activeIds) $
      execute connection ("DELETE FROM " <> tableName <> " WHERE " <> columnName <> " = ?") (DbOnly existingId)

curriculumFingerprint :: BS.ByteString -> String
curriculumFingerprint bytes =
  show (BS.length bytes)
    <> ":"
    <> show
      ( BS.foldl'
          (\accumulator currentByte -> (accumulator * 1099511628211) `xor` fromIntegral currentByte)
          (1469598103934665603 :: Word64)
          bytes
      )

renderExerciseKind :: ExerciseKind -> String
renderExerciseKind MultipleChoice = "MultipleChoice"
renderExerciseKind Cloze = "Cloze"
renderExerciseKind Ordering = "Ordering"
renderExerciseKind TrueFalse = "TrueFalse"

curriculumUnitIndex :: CurriculumUnit -> Int
curriculumUnitIndex CurriculumUnit {index} = index

curriculumUnitTitle :: CurriculumUnit -> String
curriculumUnitTitle CurriculumUnit {title} = title

curriculumLessonIndex :: CurriculumLesson -> Int
curriculumLessonIndex CurriculumLesson {index} = index

curriculumLessonTitle :: CurriculumLesson -> String
curriculumLessonTitle CurriculumLesson {title} = title
