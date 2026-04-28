module App.Runtime.Browser
  ( Browser
  , createBrowser
  ) where

import Prelude

import Effect (Effect)

type Browser =
  { render :: String -> Effect Unit
  , subscribe :: (String -> String -> Effect Unit) -> Effect (Effect Unit)
  , mountGoogleSignIn :: String -> (String -> Effect Unit) -> (String -> Effect Unit) -> Effect Unit
  , disableGoogleAutoSelect :: Effect Unit
  }

foreign import createBrowser :: Effect Browser
