module App.Runtime
  ( decodeBrowserAction
  , run
  ) where

import Prelude

import App.Http as Http
import App.Model
  ( AppState
  , Command(..)
  , Msg(..)
  , googleClientIdForSignIn
  , initialState
  , update
  )
import App.Runtime.Browser as Browser
import App.UiAction
  ( UiAction(..)
  , uiActionFromString
  )
import App.View as View
import Data.Either (Either(..))
import Data.Foldable (traverse_)
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..))
import Effect (Effect)
import Effect.Aff (attempt, launchAff_)
import Effect.Class (liftEffect)
import ReactiveEnglish.Frp.Behavior as Behavior
import ReactiveEnglish.Frp.Event as Event
import ReactiveEnglish.Frp.Network as Network

run :: Effect Unit
run = do
  browser <- Browser.createBrowser
  client <- Http.createClient
  userSource <- Event.newEvent
  asyncSource <- Event.newEvent
  network <- Network.new

  let
    messages = Event.merge userSource.event asyncSource.event
    reducers =
      Event.mapE
        (\msg state ->
          let
            result = update msg state
          in
            Tuple result.state result.commands
        )
        messages

  { behavior: stateBehavior, outputs: commandEvent } <- Behavior.mapAccumB initialState reducers

  browser.render (View.render initialState)

  cleanup <- browser.subscribe \action value ->
    case decodeBrowserAction action value of
      Just msg -> Event.push userSource.handler msg
      Nothing -> pure unit

  Network.track network cleanup
  Network.listen network (Behavior.changes stateBehavior) \state -> do
    browser.render (View.render state)
    maybeGoogleButton browser userSource.handler state
  Network.listen network commandEvent \commands ->
    traverse_ (runCommand browser client asyncSource.handler) commands

  Event.push userSource.handler AppStarted

decodeBrowserAction :: String -> String -> Maybe Msg
decodeBrowserAction action value =
  case uiActionFromString action of
    Nothing ->
      Nothing
    Just uiAction ->
      case uiAction of
        ActionSelectUnit -> Just (SelectUnit value)
        ActionPreviewLesson -> Just (PreviewLesson value)
        ActionClosePreview -> Just ClosePreview
        ActionStartLesson -> Just (StartLesson value)
        ActionChooseChoice -> ChooseChoice <$> Int.fromString value
        ActionChooseBoolean -> Just (ChooseBoolean (value == "true"))
        ActionOrderingPick -> OrderingPick <$> Int.fromString value
        ActionOrderingUnpick -> OrderingUnpick <$> Int.fromString value
        ActionSubmitText -> Just (SubmitTextAnswer value)
        ActionCheckAnswer -> Just CheckAnswer
        ActionCheckVocabularyAnswer -> Just CheckVocabularyAnswer
        ActionAdvance -> Just AdvanceAfterFeedback
        ActionStartVocabularyReview -> Just StartVocabularyReview
        ActionChooseVocabularyChoice -> ChooseVocabularyChoice <$> Int.fromString value
        ActionSubmitVocabularyText -> Just (SubmitVocabularyTextAnswer value)
        ActionAdvanceVocabulary -> Just AdvanceVocabularyReview
        ActionCloseVocabularyReview -> Just CloseVocabularyReview
        ActionBackDashboard -> Just ReturnDashboard
        ActionDismissBanner -> Just DismissBanner
        ActionRetryBootstrap -> Just AppStarted
        ActionDevLogin -> Just (RequestDevLogin value)
        ActionLogout -> Just RequestLogout

runCommand :: Browser.Browser -> Http.Client -> Event.Handler Msg -> Command -> Effect Unit
runCommand browser client sink command =
  launchAff_ do
    case command of
      LoadSessionSnapshot -> do
        result <- attempt client.loadSessionSnapshot
        case result of
          Right snapshot ->
            liftPush (SessionSnapshotLoaded snapshot)
          Left error ->
            liftPush (SessionSnapshotFailed (show error))

      ExchangeGoogleCredential credential -> do
        result <- attempt (client.exchangeGoogleCredential credential)
        case result of
          Right snapshot ->
            liftPush (AuthActionCompleted snapshot)
          Left error ->
            liftPush (AuthActionFailed (show error))

      RunDevLogin email -> do
        result <- attempt (client.runDevLogin email)
        case result of
          Right snapshot ->
            liftPush (AuthActionCompleted snapshot)
          Left error ->
            liftPush (AuthActionFailed (show error))

      Logout -> do
        liftEffect browser.disableGoogleAutoSelect
        result <- attempt client.logout
        case result of
          Right snapshot ->
            liftPush (AuthActionCompleted snapshot)
          Left error ->
            liftPush (AuthActionFailed (show error))

      LoadBootstrap -> do
        result <- attempt client.loadBootstrap
        case result of
          Right (Tuple source bootstrap) ->
            liftPush (BootstrapLoaded source bootstrap)
          Left error ->
            liftPush (BootstrapFailed (show error))

      LoadLessonPreview lessonId -> do
        result <- attempt (client.loadLessonPreview lessonId)
        case result of
          Right (Tuple source detail) ->
            liftPush (LessonPreviewLoaded source detail)
          Left error ->
            liftPush (LessonPreviewFailed (show error))

      OpenAttempt lessonId -> do
        result <- attempt (client.openAttempt lessonId)
        case result of
          Right (Tuple source attemptView) ->
            liftPush (AttemptLoaded source attemptView)
          Left error ->
            liftPush (AttemptFailed (show error))

      SendAnswer attemptId submission -> do
        result <- attempt (client.sendAnswer attemptId submission)
        case result of
          Right (Tuple source progress) ->
            liftPush (AnswerProgressLoaded source progress)
          Left error ->
            liftPush (AnswerProgressFailed (show error))

      FinishAttempt attemptId lessonId -> do
        result <- attempt (client.finishAttempt attemptId lessonId)
        case result of
          Right (Tuple source completion) ->
            liftPush (CompletionLoaded source completion)
          Left error ->
            liftPush (CompletionFailed (show error))

      LoadVocabularyReviewPrompts -> do
        result <- attempt client.loadVocabularyReview
        case result of
          Right (Tuple source prompts) ->
            liftPush (VocabularyReviewPromptsLoaded source prompts)
          Left error ->
            liftPush (VocabularyReviewPromptsFailed (show error))

      SendVocabularyReview submission -> do
        result <- attempt (client.sendVocabularyReview submission)
        case result of
          Right (Tuple source reviewResult) ->
            liftPush (VocabularyReviewLoaded source reviewResult)
          Left error ->
            liftPush (VocabularyReviewFailed (show error))
  where
  liftPush msg =
    liftEffect (Event.push sink msg)

maybeGoogleButton :: Browser.Browser -> Event.Handler Msg -> AppState -> Effect Unit
maybeGoogleButton browser sink state =
  case googleClientIdForSignIn state of
    Just clientId ->
      browser.mountGoogleSignIn clientId
        (\credential -> Event.push sink (GoogleCredentialReceived credential))
        (\message -> Event.push sink (GoogleCredentialFailed message))
    Nothing ->
      pure unit
