module Main where

import SchemaBridge.Generator (writeGeneratedModules)
import System.Environment (getArgs)

main :: IO ()
main = do
  args <- getArgs
  case args of
    [haskellOutput, pureScriptOutput] ->
      writeGeneratedModules haskellOutput pureScriptOutput
    _ ->
      error
        "usage: schema-bridge <backend-output.hs> <frontend-output.purs>"
