module Reactive.Banana.Network
  ( Network
  , listen
  , new
  , stop
  , track
  ) where

import Prelude

import Data.Array as Array
import Data.Foldable (traverse_)
import Effect (Effect)
import Effect.Ref as Ref
import Reactive.Banana.Event (Event, subscribe)

newtype Network
  = Network (Ref.Ref (Array (Effect Unit)))

new :: Effect Network
new = Network <$> Ref.new []

track :: Network -> Effect Unit -> Effect Unit
track (Network ref) cleanup =
  Ref.modify_ (Array.cons cleanup) ref

listen :: forall a. Network -> Event a -> (a -> Effect Unit) -> Effect Unit
listen network event handler = do
  cleanup <- subscribe event handler
  track network cleanup

stop :: Network -> Effect Unit
stop (Network ref) = do
  cleanups <- Ref.read ref
  traverse_ identity cleanups
  Ref.write [] ref
