module App.UiAction
  ( UiAction(..)
  , allUiActions
  , uiActionAttribute
  , uiActionFromString
  , uiActionToString
  , uiSubmitAttribute
  ) where

import Prelude (class Eq, (<>))

import Data.Maybe (Maybe(..))

data UiAction
  = ActionSelectUnit
  | ActionPreviewLesson
  | ActionClosePreview
  | ActionStartLesson
  | ActionChooseChoice
  | ActionChooseBoolean
  | ActionOrderingPick
  | ActionOrderingUnpick
  | ActionSubmitText
  | ActionCheckAnswer
  | ActionCheckVocabularyAnswer
  | ActionAdvance
  | ActionStartVocabularyReview
  | ActionChooseVocabularyChoice
  | ActionSubmitVocabularyText
  | ActionAdvanceVocabulary
  | ActionCloseVocabularyReview
  | ActionBackDashboard
  | ActionDismissBanner
  | ActionRetryBootstrap
  | ActionDevLogin
  | ActionLogout

derive instance eqUiAction :: Eq UiAction

allUiActions :: Array UiAction
allUiActions =
  [ ActionSelectUnit
  , ActionPreviewLesson
  , ActionClosePreview
  , ActionStartLesson
  , ActionChooseChoice
  , ActionChooseBoolean
  , ActionOrderingPick
  , ActionOrderingUnpick
  , ActionSubmitText
  , ActionCheckAnswer
  , ActionCheckVocabularyAnswer
  , ActionAdvance
  , ActionStartVocabularyReview
  , ActionChooseVocabularyChoice
  , ActionSubmitVocabularyText
  , ActionAdvanceVocabulary
  , ActionCloseVocabularyReview
  , ActionBackDashboard
  , ActionDismissBanner
  , ActionRetryBootstrap
  , ActionDevLogin
  , ActionLogout
  ]

uiActionToString :: UiAction -> String
uiActionToString action =
  case action of
    ActionSelectUnit -> "select-unit"
    ActionPreviewLesson -> "preview-lesson"
    ActionClosePreview -> "close-preview"
    ActionStartLesson -> "start-lesson"
    ActionChooseChoice -> "choose-choice"
    ActionChooseBoolean -> "choose-bool"
    ActionOrderingPick -> "ordering-pick"
    ActionOrderingUnpick -> "ordering-unpick"
    ActionSubmitText -> "submit-text"
    ActionCheckAnswer -> "check-answer"
    ActionCheckVocabularyAnswer -> "check-vocabulary-answer"
    ActionAdvance -> "advance"
    ActionStartVocabularyReview -> "start-vocabulary-review"
    ActionChooseVocabularyChoice -> "choose-vocab-choice"
    ActionSubmitVocabularyText -> "submit-vocab-text"
    ActionAdvanceVocabulary -> "advance-vocabulary"
    ActionCloseVocabularyReview -> "close-vocabulary-review"
    ActionBackDashboard -> "back-dashboard"
    ActionDismissBanner -> "dismiss-banner"
    ActionRetryBootstrap -> "retry-bootstrap"
    ActionDevLogin -> "dev-login"
    ActionLogout -> "logout"

uiActionFromString :: String -> Maybe UiAction
uiActionFromString value =
  case value of
    "select-unit" -> Just ActionSelectUnit
    "preview-lesson" -> Just ActionPreviewLesson
    "close-preview" -> Just ActionClosePreview
    "start-lesson" -> Just ActionStartLesson
    "choose-choice" -> Just ActionChooseChoice
    "choose-bool" -> Just ActionChooseBoolean
    "ordering-pick" -> Just ActionOrderingPick
    "ordering-unpick" -> Just ActionOrderingUnpick
    "submit-text" -> Just ActionSubmitText
    "check-answer" -> Just ActionCheckAnswer
    "check-vocabulary-answer" -> Just ActionCheckVocabularyAnswer
    "advance" -> Just ActionAdvance
    "start-vocabulary-review" -> Just ActionStartVocabularyReview
    "choose-vocab-choice" -> Just ActionChooseVocabularyChoice
    "submit-vocab-text" -> Just ActionSubmitVocabularyText
    "advance-vocabulary" -> Just ActionAdvanceVocabulary
    "close-vocabulary-review" -> Just ActionCloseVocabularyReview
    "back-dashboard" -> Just ActionBackDashboard
    "dismiss-banner" -> Just ActionDismissBanner
    "retry-bootstrap" -> Just ActionRetryBootstrap
    "dev-login" -> Just ActionDevLogin
    "logout" -> Just ActionLogout
    _ -> Nothing

uiActionAttribute :: UiAction -> String
uiActionAttribute action =
  "data-action=\"" <> uiActionToString action <> "\""

uiSubmitAttribute :: UiAction -> String
uiSubmitAttribute action =
  "data-submit=\"" <> uiActionToString action <> "\""
