{-# LANGUAGE LambdaCase #-}

module SchemaBridge.Generator
  ( writeGeneratedModules,
  )
where

import Data.List (intercalate)
import Data.Char (toLower)
import System.Directory (createDirectoryIfMissing)
import System.FilePath (takeDirectory)
import SchemaBridge.Spec

writeGeneratedModules :: FilePath -> FilePath -> IO ()
writeGeneratedModules haskellOutput pureScriptOutput = do
  createDirectoryIfMissing True (takeDirectory haskellOutput)
  createDirectoryIfMissing True (takeDirectory pureScriptOutput)
  writeFile haskellOutput renderHaskellModule
  writeFile pureScriptOutput renderPureScriptModule

renderHaskellModule :: String
renderHaskellModule =
  unlines $
    [ "{-# LANGUAGE DeriveAnyClass #-}"
    , "{-# LANGUAGE DeriveGeneric #-}"
    , "{-# LANGUAGE DerivingStrategies #-}"
    , "{-# LANGUAGE DuplicateRecordFields #-}"
    , ""
    , "module ReactiveEnglish.Schema.Generated where"
    , ""
    , "import Data.Aeson (FromJSON, ToJSON)"
    , "import GHC.Generics (Generic)"
    , ""
    ]
      <> concatMap renderHaskellDecl declarations

renderPureScriptModule :: String
renderPureScriptModule =
  unlines $
    [ "module App.Schema.Generated where"
    , ""
    , "import Prelude"
    , ""
    , "import Data.Argonaut.Decode (class DecodeJson, decodeJson)"
    , "import Data.Argonaut.Decode.Error (JsonDecodeError(..))"
    , "import Data.Argonaut.Encode (class EncodeJson, encodeJson)"
    , "import Data.Either (Either(..))"
    , "import Data.Maybe (Maybe(..))"
    , ""
    ]
      <> concatMap renderPureScriptDecl declarations

renderHaskellDecl :: Declaration -> [String]
renderHaskellDecl = \case
  EnumDeclaration name constructors ->
    [ "data " <> name
        <> " = "
        <> intercalate " | " constructors
        <> " deriving stock (Show, Eq, Ord, Enum, Bounded, Generic)"
        <> " deriving anyclass (FromJSON, ToJSON)"
    , ""
    ]
  RecordDeclaration name fields ->
    [ "data " <> name
    , "  = " <> name
    , "      {"
        <> intercalate
          "\n      , "
          [fieldName field <> " :: " <> renderHaskellType (fieldType field) | field <- fields]
        <> "\n      }"
    , "  deriving stock (Show, Eq, Generic)"
    , "  deriving anyclass (FromJSON, ToJSON)"
    , ""
    ]

renderPureScriptDecl :: Declaration -> [String]
renderPureScriptDecl = \case
  EnumDeclaration name constructors ->
    [ "data " <> name <> " = " <> intercalate " | " constructors
    , ""
    , "derive instance eq" <> name <> " :: Eq " <> name
    , "derive instance ord" <> name <> " :: Ord " <> name
    , ""
    , lowerInitial name <> "FromString :: String -> Maybe " <> name
    , lowerInitial name <> "FromString value = case value of"
    ]
      <> concatMap renderEnumFromStringCase constructors
      <> [ "  _ -> Nothing"
         , ""
         , lowerInitial name <> "ToString :: " <> name <> " -> String"
         , lowerInitial name <> "ToString value = case value of"
         ]
      <> concatMap renderEnumToStringCase constructors
      <> [ ""
         , "instance decodeJson" <> name <> " :: DecodeJson " <> name <> " where"
         , "  decodeJson json = do"
         , "    value <- decodeJson json"
         , "    case " <> lowerInitial name <> "FromString value of"
         , "      Just enumValue -> pure enumValue"
         , "      Nothing -> Left (TypeMismatch \"" <> name <> "\")"
         , ""
         , "instance encodeJson" <> name <> " :: EncodeJson " <> name <> " where"
         , "  encodeJson = encodeJson <<< " <> lowerInitial name <> "ToString"
         , ""
         ]
  RecordDeclaration name fields ->
    [ "type " <> name
    , "  ="
    , "    { "
        <> intercalate
          "\n    , "
          [fieldName field <> " :: " <> renderPureScriptType (fieldType field) | field <- fields]
        <> "\n    }"
    , ""
    ]

renderHaskellType :: TypeReference -> String
renderHaskellType = \case
  TString -> "String"
  TInt -> "Int"
  TBoolean -> "Bool"
  TMaybe inner -> "Maybe " <> renderWrappedHaskellType inner
  TArray inner -> "[" <> renderHaskellType inner <> "]"
  TNamed name -> name

renderWrappedHaskellType :: TypeReference -> String
renderWrappedHaskellType t@(TArray _) = "(" <> renderHaskellType t <> ")"
renderWrappedHaskellType t = renderHaskellType t

renderPureScriptType :: TypeReference -> String
renderPureScriptType = \case
  TString -> "String"
  TInt -> "Int"
  TBoolean -> "Boolean"
  TMaybe inner -> "Maybe " <> renderWrappedPureScriptType inner
  TArray inner -> "Array " <> renderWrappedPureScriptType inner
  TNamed name -> name

renderWrappedPureScriptType :: TypeReference -> String
renderWrappedPureScriptType t@(TMaybe _) = "(" <> renderPureScriptType t <> ")"
renderWrappedPureScriptType t@(TArray _) = "(" <> renderPureScriptType t <> ")"
renderWrappedPureScriptType t = renderPureScriptType t

renderEnumFromStringCase :: String -> [String]
renderEnumFromStringCase constructor =
  [ "  \"" <> constructor <> "\" -> Just " <> constructor
  ]

renderEnumToStringCase :: String -> [String]
renderEnumToStringCase constructor =
  [ "  " <> constructor <> " -> \"" <> constructor <> "\""
  ]

lowerInitial :: String -> String
lowerInitial [] = []
lowerInitial (first : rest) = toLower first : rest
