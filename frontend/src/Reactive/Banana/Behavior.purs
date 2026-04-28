module Reactive.Banana.Behavior
  ( Behavior
  , accumB
  , apply
  , changes
  , mapAccumB
  , mapB
  , sample
  , snapshotWith
  , stepper
  ) where

import Prelude

import Data.Tuple (Tuple(..))
import Effect (Effect)
import Effect.Ref as Ref
import Reactive.Banana.Event (Event(..), mapE, newEvent, push, subscribe)

newtype Behavior a
  = Behavior
      { current :: Effect a
      , updates :: Event a
      }

sample :: forall a. Behavior a -> Effect a
sample (Behavior behavior) = behavior.current

changes :: forall a. Behavior a -> Event a
changes (Behavior behavior) = behavior.updates

stepper :: forall a. a -> Event a -> Effect (Behavior a)
stepper initial updates = do
  currentRef <- Ref.new initial
  changeSource <- newEvent
  _ <- subscribe updates \value -> do
    Ref.write value currentRef
    push changeSource.handler value
  pure $ Behavior
    { current: Ref.read currentRef
    , updates: changeSource.event
    }

mapB :: forall a b. (a -> b) -> Behavior a -> Behavior b
mapB f behavior =
  Behavior
    { current: f <$> sample behavior
    , updates: mapE f (changes behavior)
    }

snapshotWith :: forall a b c. (a -> b -> c) -> Event a -> Behavior b -> Event c
snapshotWith f event behavior =
  let
    register listener =
      subscribe event \value -> do
        current <- sample behavior
        listener (f value current)
  in
    Event register

apply :: forall a b. Behavior (a -> b) -> Event a -> Event b
apply behavior event =
  snapshotWith (\value fn -> fn value) event behavior

accumB :: forall a. a -> Event (a -> a) -> Effect (Behavior a)
accumB initial reducers = do
  currentRef <- Ref.new initial
  changeSource <- newEvent
  _ <- subscribe reducers \step -> do
    current <- Ref.read currentRef
    let updated = step current
    Ref.write updated currentRef
    push changeSource.handler updated
  pure $ Behavior
    { current: Ref.read currentRef
    , updates: changeSource.event
    }

mapAccumB
  :: forall state output
   . state
  -> Event (state -> Tuple state output)
  -> Effect
       { behavior :: Behavior state
       , outputs :: Event output
       }
mapAccumB initial reducers = do
  currentRef <- Ref.new initial
  changeSource <- newEvent
  outputSource <- newEvent
  _ <- subscribe reducers \step -> do
    current <- Ref.read currentRef
    let Tuple updated output = step current
    Ref.write updated currentRef
    push changeSource.handler updated
    push outputSource.handler output
  pure
    { behavior:
        Behavior
          { current: Ref.read currentRef
          , updates: changeSource.event
          }
    , outputs: outputSource.event
    }
