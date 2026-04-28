module Test.Main where

import Prelude

import Effect (Effect)
import Test.App.Model as AppModel
import Test.App.UiAction as UiAction
import Test.Reactive.Banana.Test as Banana

main :: Effect Unit
main = do
  Banana.run
  AppModel.run
  UiAction.run
