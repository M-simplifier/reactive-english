module Reactive.Banana.Event
  ( Event(..)
  , Handler(..)
  , filterE
  , filterMapE
  , mapE
  , merge
  , mergeWith
  , newEvent
  , never
  , push
  , subscribe
  ) where

import Prelude

import Data.Array as Array
import Data.Foldable (traverse_)
import Data.Maybe (Maybe(..))
import Data.Tuple.Nested ((/\))
import Effect (Effect)
import Effect.Ref as Ref

type Listener a =
  { key :: Int
  , run :: a -> Effect Unit
  }

newtype Event a
  = Event ((a -> Effect Unit) -> Effect (Effect Unit))

newtype Handler a
  = Handler (a -> Effect Unit)

newEvent :: forall a. Effect { event :: Event a, handler :: Handler a }
newEvent = do
  listenersRef <- Ref.new ([] :: Array (Listener a))
  nextKeyRef <- Ref.new 0
  let
    event = Event \listener -> do
      key <- Ref.read nextKeyRef
      Ref.modify_ (_ + 1) nextKeyRef
      Ref.modify_ (\listeners -> listeners <> [{ key, run: listener }]) listenersRef
      pure $ Ref.modify_ (Array.filter (\entry -> entry.key /= key)) listenersRef

    handler = Handler \value -> do
      listeners <- Ref.read listenersRef
      traverse_ (\entry -> entry.run value) listeners

  pure { event, handler }

subscribe :: forall a. Event a -> (a -> Effect Unit) -> Effect (Effect Unit)
subscribe (Event register) = register

push :: forall a. Handler a -> a -> Effect Unit
push (Handler emit) = emit

mapE :: forall a b. (a -> b) -> Event a -> Event b
mapE f (Event register) =
  Event \listener -> register (listener <<< f)

filterE :: forall a. (a -> Boolean) -> Event a -> Event a
filterE predicate (Event register) =
  Event \listener ->
    register \value ->
      when (predicate value) (listener value)

filterMapE :: forall a b. (a -> Maybe b) -> Event a -> Event b
filterMapE f (Event register) =
  Event \listener ->
    register \value ->
      case f value of
        Just mapped -> listener mapped
        Nothing -> pure unit

merge :: forall a. Event a -> Event a -> Event a
merge left right =
  Event \listener -> do
    stopLeft <- subscribe left listener
    stopRight <- subscribe right listener
    pure do
      stopRight
      stopLeft

mergeWith :: forall a. (a -> a -> a) -> Event a -> Event a -> Event a
mergeWith _ = merge

never :: forall a. Event a
never = Event \_ -> pure (pure unit)
