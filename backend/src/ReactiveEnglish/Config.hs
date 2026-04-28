module ReactiveEnglish.Config
  ( AppConfig (..),
    DatabaseBackend (..),
    defaultAppConfig,
    parseAppConfig,
  )
where

import Data.List (isPrefixOf)
import Data.Maybe (fromMaybe)
import Text.Read (readMaybe)
import qualified System.Environment

data DatabaseBackend
  = SQLiteBackend
  | PostgresBackend
  deriving (Show, Eq)

data AppConfig = AppConfig
  { serverPort :: Int,
    databaseBackend :: DatabaseBackend,
    databasePath :: FilePath,
    databaseUrl :: Maybe String,
    curriculumPath :: FilePath,
    staticDir :: FilePath,
    googleClientId :: Maybe String,
    authDevMode :: Bool,
    authCookieName :: String,
    authCookieSecure :: Bool,
    sessionTtlHours :: Int
  }
  deriving (Show, Eq)

defaultAppConfig :: AppConfig
defaultAppConfig =
  AppConfig
    { serverPort = 8080,
      databaseBackend = SQLiteBackend,
      databasePath = "backend/reactive-english.db",
      databaseUrl = Nothing,
      curriculumPath = "curriculum/english-a2.json",
      staticDir = "frontend/dist",
      googleClientId = Nothing,
      authDevMode = False,
      authCookieName = "reactive_english_session",
      authCookieSecure = False,
      sessionTtlHours = 720
    }

parseAppConfig :: IO AppConfig
parseAppConfig = do
  envServerPort <- parseIntEnv "PORT" (serverPort defaultAppConfig)
  envDatabaseBackend <- parseDatabaseBackendEnv "DATABASE_BACKEND" SQLiteBackend
  envDatabaseUrl <- System.Environment.lookupEnv "DATABASE_URL"
  envGoogleClientId <- System.Environment.lookupEnv "GOOGLE_CLIENT_ID"
  envAuthDevMode <- parseBoolEnv "AUTH_DEV_MODE" False
  envAuthCookieName <- fromMaybe (authCookieName defaultAppConfig) <$> System.Environment.lookupEnv "SESSION_COOKIE_NAME"
  envAuthCookieSecure <- parseBoolEnv "SESSION_COOKIE_SECURE" False
  envSessionTtlHours <- parseIntEnv "SESSION_TTL_HOURS" (sessionTtlHours defaultAppConfig)
  go
    ( defaultAppConfig
        { serverPort = envServerPort,
          databaseBackend = envDatabaseBackend,
          databaseUrl = envDatabaseUrl,
          googleClientId = envGoogleClientId,
          authDevMode = envAuthDevMode,
          authCookieName = envAuthCookieName,
          authCookieSecure = envAuthCookieSecure,
          sessionTtlHours = envSessionTtlHours
        }
    )
    =<< getArgs
  where
    getArgs = System.Environment.getArgs

    go config [] = pure config
    go config ("--port" : value : rest) = go (config {serverPort = parseInt "--port" value}) rest
    go config ("--database-backend" : value : rest) = go (config {databaseBackend = parseDatabaseBackend "--database-backend" value}) rest
    go config ("--db-path" : value : rest) = go (config {databasePath = value}) rest
    go config ("--database-url" : value : rest) = go (config {databaseUrl = Just value}) rest
    go config ("--curriculum-path" : value : rest) = go (config {curriculumPath = value}) rest
    go config ("--static-dir" : value : rest) = go (config {staticDir = value}) rest
    go config (flag : rest)
      | "--port=" `isPrefixOf` flag =
          go (config {serverPort = parseInt "--port" (drop (length "--port=") flag)}) rest
      | "--database-backend=" `isPrefixOf` flag =
          go (config {databaseBackend = parseDatabaseBackend "--database-backend" (drop (length "--database-backend=") flag)}) rest
      | "--db-path=" `isPrefixOf` flag =
          go (config {databasePath = drop (length "--db-path=") flag}) rest
      | "--database-url=" `isPrefixOf` flag =
          go (config {databaseUrl = Just (drop (length "--database-url=") flag)}) rest
      | "--curriculum-path=" `isPrefixOf` flag =
          go (config {curriculumPath = drop (length "--curriculum-path=") flag}) rest
      | "--static-dir=" `isPrefixOf` flag =
          go (config {staticDir = drop (length "--static-dir=") flag}) rest
      | flag == "--help" =
          fail
            ( unlines
                [ "Usage: reactive-english-server [--port PORT] [--database-backend sqlite|postgres] [--database-url DATABASE_URL] [--db-path PATH] [--curriculum-path PATH] [--static-dir PATH]",
                  "",
                  "Defaults:",
                  "  --port 8080",
                  "  --database-backend sqlite",
                  "  --db-path backend/reactive-english.db",
                  "  --curriculum-path curriculum/english-a2.json",
                  "  --static-dir frontend/dist",
                  "",
                  "Environment:",
                  "  PORT=8080                  Server port, used by Cloud Run",
                  "  DATABASE_BACKEND=sqlite|postgres",
                  "  DATABASE_URL=...          Required when DATABASE_BACKEND=postgres",
                  "  GOOGLE_CLIENT_ID=...      Enable Sign in with Google",
                  "  AUTH_DEV_MODE=1           Enable dev-only multi-user login buttons",
                  "  SESSION_COOKIE_NAME=...   Override the session cookie name",
                  "  SESSION_COOKIE_SECURE=1   Mark the session cookie Secure",
                  "  SESSION_TTL_HOURS=720     Session lifetime in hours"
                ]
            )
      | otherwise = fail ("Unknown option: " <> flag)

    parseInt flagName value =
      case readMaybe value of
        Just parsed -> parsed
        Nothing -> errorWithoutStackTrace ("Invalid integer for " <> flagName <> ": " <> value)

    parseBool flagName value =
      case value of
        "1" -> True
        "true" -> True
        "TRUE" -> True
        "yes" -> True
        "on" -> True
        "0" -> False
        "false" -> False
        "FALSE" -> False
        "no" -> False
        "off" -> False
        _ -> errorWithoutStackTrace ("Invalid boolean for " <> flagName <> ": " <> value)

    parseBoolEnv flagName fallback = do
      maybeValue <- System.Environment.lookupEnv flagName
      pure (maybe fallback (parseBool flagName) maybeValue)

    parseDatabaseBackend flagName value =
      case value of
        "sqlite" -> SQLiteBackend
        "SQLite" -> SQLiteBackend
        "postgres" -> PostgresBackend
        "postgresql" -> PostgresBackend
        "Postgres" -> PostgresBackend
        "PostgreSQL" -> PostgresBackend
        _ -> errorWithoutStackTrace ("Invalid database backend for " <> flagName <> ": " <> value)

    parseDatabaseBackendEnv flagName fallback = do
      maybeValue <- System.Environment.lookupEnv flagName
      pure (maybe fallback (parseDatabaseBackend flagName) maybeValue)

    parseIntEnv flagName fallback = do
      maybeValue <- System.Environment.lookupEnv flagName
      pure (maybe fallback (parseInt flagName) maybeValue)
