module Test.Main where

import Prelude

import Effect (Effect)
import Test.App.Model as AppModel
import Test.App.UiAction as UiAction
import Test.ReactiveEnglish.Frp.Test as Frp

main :: Effect Unit
main = do
  Frp.run
  AppModel.run
  UiAction.run
