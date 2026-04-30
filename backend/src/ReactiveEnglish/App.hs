{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

module ReactiveEnglish.App
  ( AppEnv (..),
    application,
    closeAppEnv,
    newAppEnv,
    runServer,
  )
where

import Control.Exception (bracket)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (encode)
import Data.Proxy (Proxy (Proxy))
import Data.Tagged (Tagged (Tagged))
import Network.HTTP.Types (hContentType)
import Network.Wai (Application)
import Network.Wai.Handler.Warp (run)
import ReactiveEnglish.Api (Api)
import ReactiveEnglish.Auth
  ( AuthenticatedUser (..),
    buildSessionSnapshot,
    clearSessionCookie,
    loadViewerFromCookie,
    loginWithDev,
    loginWithGoogle,
    logoutSession,
    setSessionCookie,
  )
import ReactiveEnglish.Config (AppConfig (..), DatabaseBackend (..), parseAppConfig)
import ReactiveEnglish.Database (prepareDatabase)
import ReactiveEnglish.Db
  ( AppDb,
    DbConnection,
    closeAppDb,
    openAppDb,
    withAppDbConnection,
  )
import ReactiveEnglish.Schema.Generated
  ( ApiError (..),
    DevLoginRequest (..),
    GoogleAuthRequest (..),
  )
import ReactiveEnglish.Service
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
import ReactiveEnglish.Static (frontendApp)
import Servant
  ( Handler,
    Raw,
    Server,
    ServerError,
    addHeader,
    err400,
    err401,
    err404,
    err409,
    errBody,
    errHeaders,
    serve,
    throwError,
    (:<|>) (..),
  )
import System.Directory (createDirectoryIfMissing)
import System.FilePath (takeDirectory)

data AppEnv = AppEnv
  { config :: AppConfig,
    database :: AppDb
  }

type FullApi = Api :<|> Raw

fullApiProxy :: Proxy FullApi
fullApiProxy = Proxy

newAppEnv :: AppConfig -> IO AppEnv
newAppEnv appConfig@AppConfig {databaseBackend, databasePath, databaseUrl, curriculumPath} = do
  case databaseBackend of
    SQLiteBackend -> createDirectoryIfMissing True (takeDirectory databasePath)
    PostgresBackend -> pure ()
  appDb <- openAppDb databaseBackend databasePath databaseUrl
  withAppDbConnection appDb (`prepareDatabase` curriculumPath)
  pure AppEnv {config = appConfig, database = appDb}

closeAppEnv :: AppEnv -> IO ()
closeAppEnv = closeAppDb . database

application :: AppEnv -> Application
application appEnv =
  serve fullApiProxy (server appEnv :<|> Tagged (frontendApp (staticDir (config appEnv))))

runServer :: IO ()
runServer = do
  appConfig <- parseAppConfig
  bracket (newAppEnv appConfig) closeAppEnv $ \appEnv -> do
    let port = serverPort appConfig
        baseUrl = "http://localhost:" <> show port
    putStrLn ("Reactive English listening on " <> baseUrl)
    putStrLn ("Open " <> baseUrl <> " in your browser.")
    run port (application appEnv)

server :: AppEnv -> Server Api
server appEnv =
  sessionSnapshotHandler
    :<|> googleLoginHandler
    :<|> devLoginHandler
    :<|> logoutHandler
    :<|> protectedServer
  where
    sessionSnapshotHandler maybeCookieHeader =
      handleIO (withDbIO appEnv (\connection -> buildSessionSnapshot (config appEnv) <$> loadViewerFromCookie (config appEnv) connection maybeCookieHeader))

    googleLoginHandler GoogleAuthRequest {credential} = do
      result <- liftIO (withDbIO appEnv (\connection -> loginWithGoogle (config appEnv) connection credential))
      case result of
        Left message -> throwError (jsonError err400 message)
        Right (viewer, token) ->
          pure
            ( addHeader
                (setSessionCookie (config appEnv) token)
                (buildSessionSnapshot (config appEnv) (Just viewer))
            )

    devLoginHandler DevLoginRequest {email} = do
      result <- liftIO (withDbIO appEnv (\connection -> loginWithDev (config appEnv) connection email))
      case result of
        Left message -> throwError (jsonError err400 message)
        Right (viewer, token) ->
          pure
            ( addHeader
                (setSessionCookie (config appEnv) token)
                (buildSessionSnapshot (config appEnv) (Just viewer))
            )

    logoutHandler maybeCookieHeader = do
      liftIO (withDbIO appEnv (\connection -> logoutSession (config appEnv) connection maybeCookieHeader))
      pure
        ( addHeader
            (clearSessionCookie (config appEnv))
            (buildSessionSnapshot (config appEnv) Nothing)
        )

    protectedServer maybeCookieHeader =
      handleViewerIO appEnv maybeCookieHeader (\connection viewer -> getBootstrap connection (authenticatedUserId viewer))
        :<|> handleViewerIO appEnv maybeCookieHeader (\connection viewer -> getPlacementQuestions connection (authenticatedUserId viewer))
        :<|> (\submission -> handleViewerEither appEnv maybeCookieHeader (\connection viewer -> submitPlacement connection (authenticatedUserId viewer) submission))
        :<|> (\unitIdValue -> handleViewerMaybe appEnv maybeCookieHeader notFoundError getUnitSummaryById unitIdValue)
        :<|> (\lessonIdValue -> handleViewerMaybe appEnv maybeCookieHeader notFoundError getLessonDetailById lessonIdValue)
        :<|> (\attemptStart -> handleViewerEither appEnv maybeCookieHeader (\connection viewer -> startAttempt connection (authenticatedUserId viewer) attemptStart))
        :<|> (\attemptIdValue submission -> handleViewerEither appEnv maybeCookieHeader (\connection viewer -> submitAnswer connection (authenticatedUserId viewer) attemptIdValue submission))
        :<|> (\attemptIdValue -> handleViewerEither appEnv maybeCookieHeader (\connection viewer -> completeAttempt connection (authenticatedUserId viewer) attemptIdValue))
        :<|> handleViewerIO appEnv maybeCookieHeader (\connection viewer -> getReviewQueue connection (authenticatedUserId viewer))
        :<|> handleViewerIO appEnv maybeCookieHeader (\connection viewer -> getVocabularyDashboard connection (authenticatedUserId viewer))
        :<|> handleViewerIO appEnv maybeCookieHeader (\connection viewer -> getVocabularyReviewQueue connection (authenticatedUserId viewer))
        :<|> (\submission -> handleViewerEither appEnv maybeCookieHeader (\connection viewer -> submitVocabularyReview connection (authenticatedUserId viewer) submission))

    notFoundError resourceId = NotFoundError ("Resource not found: " <> resourceId)

handleIO :: IO value -> Handler value
handleIO action = liftIO action

withDbIO :: AppEnv -> (DbConnection -> IO value) -> IO value
withDbIO appEnv = withAppDbConnection (database appEnv)

handleViewerIO :: AppEnv -> Maybe String -> (DbConnection -> AuthenticatedUser -> IO value) -> Handler value
handleViewerIO appEnv maybeCookieHeader action = do
  viewer <- requireViewer appEnv maybeCookieHeader
  liftIO (withDbIO appEnv (\connection -> action connection viewer))

handleViewerMaybe :: AppEnv -> Maybe String -> (String -> ServiceError) -> (DbConnection -> Int -> String -> IO (Maybe value)) -> String -> Handler value
handleViewerMaybe appEnv maybeCookieHeader toServiceError action identifier = do
  viewer <- requireViewer appEnv maybeCookieHeader
  maybeValue <- liftIO (withDbIO appEnv (\connection -> action connection (authenticatedUserId viewer) identifier))
  case maybeValue of
    Just value -> pure value
    Nothing -> throwServiceError (toServiceError identifier)

handleViewerEither :: AppEnv -> Maybe String -> (DbConnection -> AuthenticatedUser -> IO (Either ServiceError value)) -> Handler value
handleViewerEither appEnv maybeCookieHeader action = do
  viewer <- requireViewer appEnv maybeCookieHeader
  result <- liftIO (withDbIO appEnv (\connection -> action connection viewer))
  either throwServiceError pure result

requireViewer :: AppEnv -> Maybe String -> Handler AuthenticatedUser
requireViewer appEnv maybeCookieHeader = do
  maybeViewer <- liftIO (withDbIO appEnv (\connection -> loadViewerFromCookie (config appEnv) connection maybeCookieHeader))
  case maybeViewer of
    Just viewer -> pure viewer
    Nothing -> throwError (jsonError err401 "You need to sign in before using the study API.")

throwServiceError :: ServiceError -> Handler value
throwServiceError serviceError =
  case serviceError of
    NotFoundError message -> throwError (jsonError err404 message)
    ConflictError message -> throwError (jsonError err409 message)
    ValidationError message -> throwError (jsonError err400 message)

jsonError :: ServerError -> String -> ServerError
jsonError servantError message =
  servantError
    { errBody = encode (ApiError {message = message}),
      errHeaders = [(hContentType, "application/json; charset=utf-8")] <> errHeaders servantError
    }
