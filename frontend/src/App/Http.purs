module App.Http
  ( Client
  , createClient
  ) where

import Prelude (Unit, bind, discard, pure, (<>))

import App.Model (DataSource(..))
import App.Schema.Generated
  ( AnswerSubmission
  , AppBootstrap
  , AttemptCompletion
  , AttemptProgress
  , AttemptStart
  , AttemptView
  , DevLoginRequest
  , GoogleAuthRequest
  , LessonDetail
  , SessionSnapshot
  , VocabularyReviewPrompt
  , VocabularyReviewResult
  , VocabularyReviewSubmission
  )
import Data.Argonaut.Core (stringify)
import Data.Argonaut.Decode (class DecodeJson, decodeJson)
import Data.Argonaut.Decode.Error (printJsonDecodeError)
import Data.Argonaut.Encode (class EncodeJson, encodeJson)
import Data.Argonaut.Parser (jsonParser)
import Data.Either (Either(..))
import Data.Tuple (Tuple(..))
import Effect (Effect)
import Effect.Aff (Aff, makeAff, nonCanceler)
import Effect.Class (liftEffect)
import Effect.Exception (error, throw)

type Client =
  { loadSessionSnapshot :: Aff SessionSnapshot
  , exchangeGoogleCredential :: String -> Aff SessionSnapshot
  , runDevLogin :: String -> Aff SessionSnapshot
  , logout :: Aff SessionSnapshot
  , loadBootstrap :: Aff (Tuple DataSource AppBootstrap)
  , loadLessonPreview :: String -> Aff (Tuple DataSource LessonDetail)
  , openAttempt :: String -> Aff (Tuple DataSource AttemptView)
  , sendAnswer :: String -> AnswerSubmission -> Aff (Tuple DataSource AttemptProgress)
  , finishAttempt :: String -> String -> Aff (Tuple DataSource AttemptCompletion)
  , loadVocabularyReview :: Aff (Tuple DataSource (Array VocabularyReviewPrompt))
  , sendVocabularyReview :: VocabularyReviewSubmission -> Aff (Tuple DataSource VocabularyReviewResult)
  }

foreign import requestJsonImpl
  :: String
  -> String
  -> String
  -> (String -> Effect Unit)
  -> (String -> Effect Unit)
  -> Effect Unit

createClient :: Effect Client
createClient =
  pure
    { loadSessionSnapshot:
        requestNoBody "GET" "/api/session"
    , exchangeGoogleCredential: \credential ->
        requestJson "POST" "/api/auth/google" ({ credential } :: GoogleAuthRequest)
    , runDevLogin: \email ->
        requestJson "POST" "/api/auth/dev" ({ email } :: DevLoginRequest)
    , logout:
        requestNoBody "POST" "/api/logout"
    , loadBootstrap:
        withLiveData (requestNoBody "GET" "/api/bootstrap")
    , loadLessonPreview: \lessonId ->
        withLiveData (requestNoBody "GET" ("/api/lessons/" <> lessonId))
    , openAttempt: \lessonId ->
        withLiveData (requestJson "POST" "/api/attempts" ({ lessonId } :: AttemptStart))
    , sendAnswer: \attemptId submission ->
        withLiveData (requestJson "POST" ("/api/attempts/" <> attemptId <> "/answer") submission)
    , finishAttempt: \attemptId _ ->
        withLiveData (requestNoBody "POST" ("/api/attempts/" <> attemptId <> "/complete"))
    , loadVocabularyReview:
        withLiveData (requestNoBody "GET" "/api/vocabulary/review")
    , sendVocabularyReview: \submission ->
        withLiveData (requestJson "POST" "/api/vocabulary/review" submission)
    }

withLiveData :: forall a. Aff a -> Aff (Tuple DataSource a)
withLiveData action = do
  value <- action
  pure (Tuple LiveBackend value)

requestJson
  :: forall request response
   . EncodeJson request
  => DecodeJson response
  => String
  -> String
  -> request
  -> Aff response
requestJson method url body = do
  raw <- requestText method url (stringify (encodeJson body))
  decodeResponse url raw

requestNoBody :: forall response. DecodeJson response => String -> String -> Aff response
requestNoBody method url = do
  raw <- requestText method url ""
  decodeResponse url raw

decodeResponse :: forall response. DecodeJson response => String -> String -> Aff response
decodeResponse url raw =
  case jsonParser raw of
    Left parseError ->
      liftEffect (throw ("Invalid JSON from " <> url <> ": " <> parseError))

    Right json ->
      case decodeJson json of
        Left decodeError ->
          liftEffect (throw ("JSON decode failed for " <> url <> ": " <> printJsonDecodeError decodeError))

        Right value ->
          pure value

requestText :: String -> String -> String -> Aff String
requestText method url body =
  makeAff \done -> do
    requestJsonImpl method url body
      (\responseText -> done (Right responseText))
      (\message -> done (Left (error message)))
    pure nonCanceler
