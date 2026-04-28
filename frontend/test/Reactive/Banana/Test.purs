module Test.Reactive.Banana.Test
  ( run
  ) where

import Prelude

import Data.Array as Array
import Data.Tuple (Tuple(..))
import Effect (Effect)
import Effect.Ref as Ref
import Reactive.Banana.Behavior as Behavior
import Reactive.Banana.Event as Event
import Test.Assert (assert)

run :: Effect Unit
run = do
  testEventMapFilter
  testStepper
  testMapAccum

testEventMapFilter :: Effect Unit
testEventMapFilter = do
  source <- Event.newEvent
  valuesRef <- Ref.new ([] :: Array Int)
  stop <-
    Event.subscribe
      (Event.filterE (\value -> value > 2) (Event.mapE (_ * 2) source.event))
      (\value -> Ref.modify_ (_ <> [ value ]) valuesRef)
  Event.push source.handler 1
  Event.push source.handler 2
  Event.push source.handler 4
  values <- Ref.read valuesRef
  stop
  assert (values == [ 4, 8 ])

testStepper :: Effect Unit
testStepper = do
  source <- Event.newEvent
  behavior <- Behavior.stepper 0 source.event
  Event.push source.handler 7
  Event.push source.handler 11
  current <- Behavior.sample behavior
  assert (current == 11)

testMapAccum :: Effect Unit
testMapAccum = do
  source <- Event.newEvent
  outputsRef <- Ref.new ([] :: Array String)
  network <- Behavior.mapAccumB 0 (Event.mapE (\value total -> Tuple (total + value) ("+" <> show value)) source.event)
  stop <- Event.subscribe network.outputs (\label -> Ref.modify_ (_ <> [ label ]) outputsRef)
  Event.push source.handler 2
  Event.push source.handler 5
  total <- Behavior.sample network.behavior
  labels <- Ref.read outputsRef
  stop
  assert (total == 7)
  assert (labels == [ "+2", "+5" ])
