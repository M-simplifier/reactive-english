module Test.App.UiAction
  ( run
  ) where

import Prelude (Unit, discard, map, not, (==), (||))

import App.Fixtures (initialBootstrap)
import App.Model
  ( AppState
  , DataSource(..)
  , Msg(..)
  , initialState
  , update
  )
import App.Runtime (decodeBrowserAction)
import App.Schema.Generated
  ( AuthProvider(..)
  , SessionSnapshot
  )
import App.UiAction
  ( UiAction(..)
  , allUiActions
  , uiActionAttribute
  , uiActionFromString
  , uiActionToString
  )
import App.View as View
import Data.Array as Array
import Data.Foldable (all)
import Data.Maybe (Maybe(..))
import Data.String (Pattern(..))
import Data.String.CodeUnits as String
import Effect (Effect)
import Test.Assert (assert)

run :: Effect Unit
run = do
  testUiActionRoundTrips
  testUiActionStringsAreUnique
  testRuntimeDecodesEveryUiAction
  testVocabularyCheckActionDecodesToVocabularyMessage
  testRenderedVocabularyCheckUsesTypedAction
  testRenderedPlacementStartUsesTypedAction

testUiActionRoundTrips :: Effect Unit
testUiActionRoundTrips =
  assert (all (\action -> uiActionFromString (uiActionToString action) == Just action) allUiActions)

testUiActionStringsAreUnique :: Effect Unit
testUiActionStringsAreUnique =
  assert (not (hasDuplicateStrings (map uiActionToString allUiActions)))

testRuntimeDecodesEveryUiAction :: Effect Unit
testRuntimeDecodesEveryUiAction =
  assert
    ( all
        ( \action ->
            case decodeBrowserAction (uiActionToString action) (sampleBrowserValue action) of
              Just _ -> true
              Nothing -> false
        )
        allUiActions
    )

testVocabularyCheckActionDecodesToVocabularyMessage :: Effect Unit
testVocabularyCheckActionDecodesToVocabularyMessage =
  assert
    ( case decodeBrowserAction (uiActionToString ActionCheckVocabularyAnswer) "" of
        Just CheckVocabularyAnswer -> true
        _ -> false
    )

testRenderedVocabularyCheckUsesTypedAction :: Effect Unit
testRenderedVocabularyCheckUsesTypedAction =
  let
    html = View.render authedVocabularyState
  in
    assert (String.contains (Pattern (uiActionAttribute ActionCheckVocabularyAnswer)) html)

testRenderedPlacementStartUsesTypedAction :: Effect Unit
testRenderedPlacementStartUsesTypedAction =
  let
    html = View.render authedDashboardState
  in
    assert (String.contains (Pattern (uiActionAttribute ActionStartPlacement)) html)

sampleBrowserValue :: UiAction -> String
sampleBrowserValue action =
  case action of
    ActionChooseChoice -> "0"
    ActionOrderingPick -> "0"
    ActionOrderingUnpick -> "0"
    ActionChooseVocabularyChoice -> "0"
    ActionChoosePlacementChoice -> "0"
    ActionChooseBoolean -> "true"
    _ -> "sample"

hasDuplicateStrings :: Array String -> Boolean
hasDuplicateStrings values =
  case Array.uncons values of
    Nothing -> false
    Just { head, tail } -> Array.elem head tail || hasDuplicateStrings tail

authedVocabularyState :: AppState
authedVocabularyState =
  let
    authed = update (SessionSnapshotLoaded signedInSession) initialState
    dashboard = update (BootstrapLoaded LiveBackend initialBootstrap) authed.state
    opened = update StartVocabularyReview dashboard.state
  in
    opened.state

authedDashboardState :: AppState
authedDashboardState =
  let
    authed = update (SessionSnapshotLoaded signedInSession) initialState
    dashboard = update (BootstrapLoaded LiveBackend initialBootstrap) authed.state
  in
    dashboard.state

signedInSession :: SessionSnapshot
signedInSession =
  { viewer:
      Just
        { displayName: "Learner"
        , email: "learner@example.com"
        , avatarUrl: Nothing
        , provider: Google
        }
  , authConfig:
      { googleEnabled: true
      , googleClientId: Just "test-client-id"
      , devLoginEnabled: true
      , devLoginOptions:
          [ { email: "alex@dev.local", displayName: "Alex Dev" }
          ]
      }
  }
