{-# LANGUAGE CPP #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}

module ReactiveEnglish.Auth
  ( AuthenticatedUser (..),
    GoogleCredentialFailure (..),
    GoogleEmailVerifiedWire (..),
    GoogleTokenClaims (..),
    GoogleTokenInfo (..),
    buildSessionSnapshot,
    clearSessionCookie,
    defaultDevLoginOptions,
    loadViewerFromCookie,
    loginWithDev,
    loginWithGoogle,
    logoutSession,
    normalizeGoogleEmailVerified,
    normalizeGoogleTokenInfo,
    setSessionCookie,
    validateGoogleTokenClaims,
  )
where

import Control.Applicative ((<|>))
import qualified Data.Aeson as Aeson
import Data.Aeson ((.:), (.:?), FromJSON, withObject)
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import Data.List (find)
import Data.Maybe (fromMaybe, listToMaybe)
import qualified Data.Text as Text
import Data.Time.Clock (addUTCTime, getCurrentTime)
import Data.Time.Clock.POSIX (getPOSIXTime)
#ifdef POSTGRES_BACKEND
import qualified Database.PostgreSQL.Simple.FromRow as PGFromRow
#endif
import qualified Database.SQLite.Simple.FromRow as SQLiteFromRow
import Text.Read (readMaybe)
import Network.HTTP.Simple
  ( getResponseBody,
    httpLBS,
    parseRequest,
  )
import Network.HTTP.Types.URI (urlEncode)
import ReactiveEnglish.Config (AppConfig (..))
import ReactiveEnglish.Db
  ( DbConnection,
    DbOnly (..),
    execute,
    insertReturningId,
    query,
    withTransaction,
  )
import ReactiveEnglish.Schema.Generated
  ( AuthConfig (..),
    AuthProvider (..),
    DevLoginOption (..),
    SessionSnapshot (..),
    UserSummary (..),
  )
import qualified System.Entropy as Entropy
import Web.Cookie
  ( SetCookie,
    defaultSetCookie,
    parseCookies,
    sameSiteLax,
    setCookieHttpOnly,
    setCookieMaxAge,
    setCookieName,
    setCookiePath,
    setCookieSameSite,
    setCookieSecure,
    setCookieValue,
  )

data AuthenticatedUser = AuthenticatedUser
  { authenticatedUserId :: Int,
    authenticatedUserDisplayName :: String,
    authenticatedUserEmail :: String,
    authenticatedUserAvatarUrl :: Maybe String,
    authenticatedUserProvider :: AuthProvider
  }
  deriving (Show, Eq)

data VerifiedIdentity = VerifiedIdentity
  { verifiedIdentityProvider :: AuthProvider,
    verifiedIdentityProviderUserId :: String,
    verifiedIdentityDisplayName :: String,
    verifiedIdentityEmail :: String,
    verifiedIdentityAvatarUrl :: Maybe String
  }

data LoginResult = LoginResult
  { user :: AuthenticatedUser,
    sessionToken :: String
  }

data ViewerRow = ViewerRow
  { rowUserId :: Int,
    rowDisplayName :: String,
    rowEmail :: String,
    rowAvatarUrl :: Maybe String,
    rowProvider :: String
  }

instance SQLiteFromRow.FromRow ViewerRow where
  fromRow =
    ViewerRow
      <$> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field
      <*> SQLiteFromRow.field

#ifdef POSTGRES_BACKEND
instance PGFromRow.FromRow ViewerRow where
  fromRow =
    ViewerRow
      <$> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
      <*> PGFromRow.field
#endif

data UserIdRow = UserIdRow
  { rowExistingUserId :: Int
  }

instance SQLiteFromRow.FromRow UserIdRow where
  fromRow = UserIdRow <$> SQLiteFromRow.field

#ifdef POSTGRES_BACKEND
instance PGFromRow.FromRow UserIdRow where
  fromRow = UserIdRow <$> PGFromRow.field
#endif

data GoogleCredentialFailure
  = GoogleCredentialEmailVerifiedMissing
  | GoogleCredentialEmailVerifiedMalformed
  | GoogleCredentialExpirationMalformed
  | GoogleCredentialIssuerInvalid
  | GoogleCredentialAudienceMismatch
  | GoogleCredentialExpired
  | GoogleCredentialEmailNotVerified
  deriving (Show, Eq)

data GoogleEmailVerifiedWire
  = GoogleEmailVerifiedBool Bool
  | GoogleEmailVerifiedString Text.Text
  deriving (Show, Eq)

instance FromJSON GoogleEmailVerifiedWire where
  parseJSON value =
    case value of
      Aeson.Bool boolValue ->
        pure (GoogleEmailVerifiedBool boolValue)
      Aeson.String textValue ->
        pure (GoogleEmailVerifiedString textValue)
      _ ->
        AesonTypes.typeMismatch "Bool or boolean string" value

data GoogleTokenInfo = GoogleTokenInfo
  { tokenAud :: String,
    tokenIss :: String,
    tokenSub :: Text.Text,
    tokenEmail :: Text.Text,
    tokenEmailVerified :: Maybe GoogleEmailVerifiedWire,
    tokenName :: Maybe Text.Text,
    tokenPicture :: Maybe Text.Text,
    tokenExp :: Maybe String
  }
  deriving (Show, Eq)

data GoogleTokenClaims = GoogleTokenClaims
  { claimAud :: String,
    claimIss :: String,
    claimSub :: String,
    claimEmail :: String,
    claimEmailVerified :: Bool,
    claimName :: Maybe String,
    claimPicture :: Maybe String,
    claimExp :: Maybe Integer
  }
  deriving (Show, Eq)

instance FromJSON GoogleTokenInfo where
  parseJSON =
    withObject "GoogleTokenInfo" $ \objectValue ->
      GoogleTokenInfo
        <$> objectValue .: "aud"
        <*> objectValue .: "iss"
        <*> objectValue .: "sub"
        <*> objectValue .: "email"
        <*> objectValue .:? "email_verified"
        <*> objectValue .:? "name"
        <*> objectValue .:? "picture"
        <*> objectValue .:? "exp"

normalizeGoogleEmailVerified :: Maybe GoogleEmailVerifiedWire -> Either GoogleCredentialFailure Bool
normalizeGoogleEmailVerified maybeWireValue =
  case maybeWireValue of
    Nothing ->
      Left GoogleCredentialEmailVerifiedMissing
    Just (GoogleEmailVerifiedBool boolValue) ->
      Right boolValue
    Just (GoogleEmailVerifiedString textValue) ->
      case Text.toLower (Text.strip textValue) of
        "true" -> Right True
        "false" -> Right False
        _ -> Left GoogleCredentialEmailVerifiedMalformed

normalizeGoogleTokenInfo :: GoogleTokenInfo -> Either GoogleCredentialFailure GoogleTokenClaims
normalizeGoogleTokenInfo GoogleTokenInfo {tokenAud, tokenIss, tokenSub, tokenEmail, tokenEmailVerified, tokenName, tokenPicture, tokenExp} = do
  normalizedEmailVerified <- normalizeGoogleEmailVerified tokenEmailVerified
  normalizedExp <- normalizeGoogleExpiration tokenExp
  pure
    GoogleTokenClaims
      { claimAud = tokenAud,
        claimIss = tokenIss,
        claimSub = Text.unpack tokenSub,
        claimEmail = Text.unpack tokenEmail,
        claimEmailVerified = normalizedEmailVerified,
        claimName = Text.unpack <$> tokenName,
        claimPicture = Text.unpack <$> tokenPicture,
        claimExp = normalizedExp
      }

normalizeGoogleExpiration :: Maybe String -> Either GoogleCredentialFailure (Maybe Integer)
normalizeGoogleExpiration maybeExp =
  case maybeExp of
    Nothing ->
      Right Nothing
    Just expText ->
      case readMaybe expText of
        Just expSeconds -> Right (Just expSeconds)
        Nothing -> Left GoogleCredentialExpirationMalformed

validateGoogleTokenClaims :: String -> Integer -> GoogleTokenClaims -> Either GoogleCredentialFailure ()
validateGoogleTokenClaims clientId now GoogleTokenClaims {claimAud, claimIss, claimEmailVerified, claimExp}
  | not (googleIssuerIsValid claimIss) = Left GoogleCredentialIssuerInvalid
  | claimAud /= clientId = Left GoogleCredentialAudienceMismatch
  | not (googleExpiryIsValid now claimExp) = Left GoogleCredentialExpired
  | not claimEmailVerified = Left GoogleCredentialEmailNotVerified
  | otherwise = Right ()

googleIssuerIsValid :: String -> Bool
googleIssuerIsValid issuerValue =
  issuerValue == "accounts.google.com"
    || issuerValue == "https://accounts.google.com"

googleExpiryIsValid :: Integer -> Maybe Integer -> Bool
googleExpiryIsValid now maybeExp =
  case maybeExp of
    Nothing -> True
    Just expirySeconds -> expirySeconds >= now

defaultDevLoginOptions :: [DevLoginOption]
defaultDevLoginOptions =
  [ DevLoginOption {email = "alex@dev.local", displayName = "Alex Dev"},
    DevLoginOption {email = "jamie@dev.local", displayName = "Jamie Dev"},
    DevLoginOption {email = "sam@dev.local", displayName = "Sam Dev"}
  ]

buildSessionSnapshot :: AppConfig -> Maybe AuthenticatedUser -> SessionSnapshot
buildSessionSnapshot config maybeViewer =
  SessionSnapshot
    { viewer = toUserSummary <$> maybeViewer,
      authConfig =
        AuthConfig
          { googleEnabled = maybe False (const True) (configGoogleClientId config),
            googleClientId = configGoogleClientId config,
            devLoginEnabled = configAuthDevMode config,
            devLoginOptions = if configAuthDevMode config then defaultDevLoginOptions else []
          }
    }

loadViewerFromCookie :: AppConfig -> DbConnection -> Maybe String -> IO (Maybe AuthenticatedUser)
loadViewerFromCookie config connection maybeCookieHeader =
  case extractSessionToken config maybeCookieHeader of
    Nothing -> pure Nothing
    Just token -> do
      now <- getCurrentTime
      rows <-
        query
          connection
          "SELECT u.user_id, u.display_name, u.email, u.avatar_url, s.provider FROM sessions s JOIN users u ON u.user_id = s.user_id WHERE s.session_id = ? AND s.expires_at > ? LIMIT 1"
          (token, now)
      case listToMaybe rows of
        Nothing -> pure Nothing
        Just ViewerRow {rowUserId, rowDisplayName, rowEmail, rowAvatarUrl, rowProvider} -> do
          execute connection "UPDATE sessions SET last_seen_at = ? WHERE session_id = ?" (now, token)
          pure
            ( Just
                AuthenticatedUser
                  { authenticatedUserId = rowUserId,
                    authenticatedUserDisplayName = rowDisplayName,
                    authenticatedUserEmail = rowEmail,
                    authenticatedUserAvatarUrl = rowAvatarUrl,
                    authenticatedUserProvider = parseAuthProvider rowProvider
                  }
            )

loginWithDev :: AppConfig -> DbConnection -> String -> IO (Either String (AuthenticatedUser, String))
loginWithDev config connection requestedEmail =
  if not (authDevMode config)
    then pure (Left "Development login is disabled.")
    else
      case find (\DevLoginOption {email} -> email == requestedEmail) defaultDevLoginOptions of
        Nothing -> pure (Left ("Unknown development login: " <> requestedEmail))
        Just DevLoginOption {email, displayName} -> do
          LoginResult {user, sessionToken} <-
            loginWithIdentity
              connection
              config
              VerifiedIdentity
                { verifiedIdentityProvider = Dev,
                  verifiedIdentityProviderUserId = email,
                  verifiedIdentityDisplayName = displayName,
                  verifiedIdentityEmail = email,
                  verifiedIdentityAvatarUrl = Nothing
                }
          pure (Right (user, sessionToken))

loginWithGoogle :: AppConfig -> DbConnection -> String -> IO (Either String (AuthenticatedUser, String))
loginWithGoogle config connection credential =
  case configGoogleClientId config of
    Nothing -> pure (Left "Google Sign-In is not configured on this server.")
    Just clientId -> do
      identityResult <- verifyGoogleCredential clientId credential
      case identityResult of
        Left message -> pure (Left message)
        Right verifiedIdentity -> do
          LoginResult {user, sessionToken} <- loginWithIdentity connection config verifiedIdentity
          pure (Right (user, sessionToken))

logoutSession :: AppConfig -> DbConnection -> Maybe String -> IO ()
logoutSession config connection maybeCookieHeader =
  case extractSessionToken config maybeCookieHeader of
    Nothing -> pure ()
    Just token -> execute connection "DELETE FROM sessions WHERE session_id = ?" (DbOnly token)

setSessionCookie :: AppConfig -> String -> SetCookie
setSessionCookie config token =
  defaultSetCookie
    { setCookieName = BS8.pack (authCookieName config),
      setCookieValue = BS8.pack token,
      setCookiePath = Just "/",
      setCookieHttpOnly = True,
      setCookieSameSite = Just sameSiteLax,
      setCookieSecure = authCookieSecure config,
      setCookieMaxAge = Just (fromIntegral (sessionTtlHours config * 3600))
    }

clearSessionCookie :: AppConfig -> SetCookie
clearSessionCookie config =
  defaultSetCookie
    { setCookieName = BS8.pack (authCookieName config),
      setCookieValue = "",
      setCookiePath = Just "/",
      setCookieHttpOnly = True,
      setCookieSameSite = Just sameSiteLax,
      setCookieSecure = authCookieSecure config,
      setCookieMaxAge = Just 0
    }

loginWithIdentity :: DbConnection -> AppConfig -> VerifiedIdentity -> IO LoginResult
loginWithIdentity connection config identity =
  withTransaction connection $ do
    now <- getCurrentTime
    maybeExistingIdentity <-
      listToMaybe
        <$> query
          connection
          "SELECT user_id FROM auth_identities WHERE provider = ? AND provider_user_id = ? LIMIT 1"
          (renderAuthProvider (verifiedIdentityProvider identity), verifiedIdentityProviderUserId identity)
    maybeExistingEmail <-
      listToMaybe
        <$> query
          connection
          "SELECT user_id FROM users WHERE email = ? LIMIT 1"
          (DbOnly (verifiedIdentityEmail identity))
    userIdValue <-
      case maybeExistingIdentity <|> maybeExistingEmail of
        Just UserIdRow {rowExistingUserId} -> do
          execute
            connection
            "UPDATE users SET display_name = ?, email = ?, avatar_url = ?, updated_at = ?, last_login_at = ? WHERE user_id = ?"
            (verifiedIdentityDisplayName identity, verifiedIdentityEmail identity, verifiedIdentityAvatarUrl identity, now, now, rowExistingUserId)
          pure rowExistingUserId
        Nothing ->
          insertReturningId
            connection
            "INSERT INTO users (display_name, email, avatar_url, created_at, updated_at, last_login_at) VALUES (?, ?, ?, ?, ?, ?)"
            "INSERT INTO users (display_name, email, avatar_url, created_at, updated_at, last_login_at) VALUES (?, ?, ?, ?, ?, ?) RETURNING user_id"
            (verifiedIdentityDisplayName identity, verifiedIdentityEmail identity, verifiedIdentityAvatarUrl identity, now, now, now)
    execute
      connection
      "INSERT INTO auth_identities (provider, provider_user_id, user_id, email, display_name, avatar_url, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT (provider, provider_user_id) DO UPDATE SET user_id = excluded.user_id, email = excluded.email, display_name = excluded.display_name, avatar_url = excluded.avatar_url, updated_at = excluded.updated_at"
      ( renderAuthProvider (verifiedIdentityProvider identity),
        verifiedIdentityProviderUserId identity,
        userIdValue,
        verifiedIdentityEmail identity,
        verifiedIdentityDisplayName identity,
        verifiedIdentityAvatarUrl identity,
        now,
        now
      )
    execute
      connection
      "INSERT INTO user_profiles (user_id, xp, streak_days, last_active_day) VALUES (?, 0, 0, NULL) ON CONFLICT (user_id) DO NOTHING"
      (DbOnly userIdValue)
    execute connection "DELETE FROM sessions WHERE expires_at <= ?" (DbOnly now)
    token <- generateSessionToken
    let expiresAt = addUTCTime (fromIntegral (sessionTtlHours config * 3600)) now
    execute
      connection
      "INSERT INTO sessions (session_id, user_id, provider, created_at, expires_at, last_seen_at) VALUES (?, ?, ?, ?, ?, ?)"
      (token, userIdValue, renderAuthProvider (verifiedIdentityProvider identity), now, expiresAt, now)
    pure
      LoginResult
        { user =
            AuthenticatedUser
              { authenticatedUserId = userIdValue,
                authenticatedUserDisplayName = verifiedIdentityDisplayName identity,
                authenticatedUserEmail = verifiedIdentityEmail identity,
                authenticatedUserAvatarUrl = verifiedIdentityAvatarUrl identity,
                authenticatedUserProvider = verifiedIdentityProvider identity
              },
          sessionToken = token
        }

verifyGoogleCredential :: String -> String -> IO (Either String VerifiedIdentity)
verifyGoogleCredential clientId credential = do
  request <-
    parseRequest
      ( "https://oauth2.googleapis.com/tokeninfo?id_token="
          <> BS8.unpack (urlEncode True (BS8.pack credential))
      )
  response <- httpLBS request
  case Aeson.eitherDecode (getResponseBody response) of
    Left decodeError ->
      pure (Left ("Could not decode Google token verification response: " <> decodeError))
    Right tokenInfo -> do
      now <- (round <$> getPOSIXTime) :: IO Integer
      pure $
        case do
          claims <- normalizeGoogleTokenInfo tokenInfo
          validateGoogleTokenClaims clientId now claims
          pure (verifiedIdentityFromClaims claims) of
          Left failure -> Left (renderGoogleCredentialFailure failure)
          Right identity -> Right identity

renderGoogleCredentialFailure :: GoogleCredentialFailure -> String
renderGoogleCredentialFailure failure =
  case failure of
    GoogleCredentialEmailVerifiedMissing -> "Google credential did not include an email verification claim."
    GoogleCredentialEmailVerifiedMalformed -> "Google credential email verification claim was not a recognized boolean."
    GoogleCredentialExpirationMalformed -> "Google credential expiration claim was not a valid timestamp."
    GoogleCredentialIssuerInvalid -> "Google credential issuer was not recognized."
    GoogleCredentialAudienceMismatch -> "Google credential audience did not match this app."
    GoogleCredentialExpired -> "Google credential has expired."
    GoogleCredentialEmailNotVerified -> "Google credential email is not verified."

verifiedIdentityFromClaims :: GoogleTokenClaims -> VerifiedIdentity
verifiedIdentityFromClaims GoogleTokenClaims {claimSub, claimEmail, claimName, claimPicture} =
  VerifiedIdentity
    { verifiedIdentityProvider = Google,
      verifiedIdentityProviderUserId = claimSub,
      verifiedIdentityDisplayName = fromMaybe claimEmail claimName,
      verifiedIdentityEmail = claimEmail,
      verifiedIdentityAvatarUrl = claimPicture
    }

generateSessionToken :: IO String
generateSessionToken = toHex <$> Entropy.getEntropy 32

extractSessionToken :: AppConfig -> Maybe String -> Maybe String
extractSessionToken config maybeCookieHeader = do
  headerValue <- maybeCookieHeader
  cookieValue <- lookup (BS8.pack (authCookieName config)) (parseCookies (BS8.pack headerValue))
  pure (BS8.unpack cookieValue)

toUserSummary :: AuthenticatedUser -> UserSummary
toUserSummary AuthenticatedUser {authenticatedUserDisplayName, authenticatedUserEmail, authenticatedUserAvatarUrl, authenticatedUserProvider} =
  UserSummary
    { displayName = authenticatedUserDisplayName,
      email = authenticatedUserEmail,
      avatarUrl = authenticatedUserAvatarUrl,
      provider = authenticatedUserProvider
    }

renderAuthProvider :: AuthProvider -> String
renderAuthProvider Google = "Google"
renderAuthProvider Dev = "Dev"

parseAuthProvider :: String -> AuthProvider
parseAuthProvider "Google" = Google
parseAuthProvider "Dev" = Dev
parseAuthProvider unknownProvider = errorWithoutStackTrace ("Unknown auth provider: " <> unknownProvider)

configGoogleClientId :: AppConfig -> Maybe String
configGoogleClientId AppConfig {googleClientId} = googleClientId

configAuthDevMode :: AppConfig -> Bool
configAuthDevMode AppConfig {authDevMode} = authDevMode

toHex :: BS.ByteString -> String
toHex =
  BS8.unpack . BS.concatMap encodeByte
  where
    hexChars = "0123456789abcdef"
    hexChar index = BS8.index hexChars index
    encodeByte byte =
      BS8.pack
        [ hexChar (fromIntegral byte `div` 16),
          hexChar (fromIntegral byte `mod` 16)
        ]
