{-# LANGUAGE OverloadedStrings #-}

module ReactiveEnglish.Static
  ( frontendApp,
  )
where

import qualified Data.ByteString.Char8 as BS8
import Data.ByteString (ByteString)
import Data.List (isInfixOf)
import qualified Data.Text as T
import qualified Data.ByteString.Lazy.Char8 as BL8
import Network.HTTP.Types (hContentType, methodGet, methodHead, status404, status200)
import Network.Wai (Application, pathInfo, requestMethod, responseFile, responseLBS)
import System.Directory (doesDirectoryExist, doesFileExist)
import System.FilePath ((</>), takeExtension)

frontendApp :: FilePath -> Application
frontendApp staticDir request respond = do
  let pathSegments = map T.unpack (pathInfo request)
      requestedPath = foldl (</>) staticDir pathSegments
      indexPath = staticDir </> "index.html"
      safeMethod = requestMethod request == methodGet || requestMethod request == methodHead
  requestedFileExists <- doesFileExist requestedPath
  requestedDirectoryExists <- doesDirectoryExist requestedPath
  indexExists <- doesFileExist indexPath
  if requestedFileExists || requestedDirectoryExists || wantsAsset pathSegments
    then do
      let assetPath =
            if requestedDirectoryExists
              then requestedPath </> "index.html"
              else requestedPath
      assetExists <- doesFileExist assetPath
      if assetExists
        then respond (responseFile status200 [(hContentType, mimeTypeFor assetPath)] assetPath Nothing)
        else missingBuild
    else
      if safeMethod && indexExists
        then respond (responseFile status200 [(hContentType, "text/html; charset=utf-8")] indexPath Nothing)
        else missingBuild
  where
    missingBuild =
      respond
            ( responseLBS
                status404
                [(hContentType, "text/plain; charset=utf-8")]
                (BL8.pack "Frontend build not found. Build frontend/dist before loading the SPA.")
            )

wantsAsset :: [FilePath] -> Bool
wantsAsset [] = False
wantsAsset pathSegments = any ('.' `elem`) pathSegments || "assets" `elem` pathSegments || any ("static" `isInfixOf`) pathSegments

mimeTypeFor :: FilePath -> ByteString
mimeTypeFor path =
  case takeExtension path of
    ".html" -> "text/html; charset=utf-8"
    ".js" -> "application/javascript; charset=utf-8"
    ".css" -> "text/css; charset=utf-8"
    ".json" -> "application/json; charset=utf-8"
    ".svg" -> "image/svg+xml"
    ".png" -> "image/png"
    ".jpg" -> "image/jpeg"
    ".jpeg" -> "image/jpeg"
    _ -> "application/octet-stream"
