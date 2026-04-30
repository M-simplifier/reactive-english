{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Exception (bracket)
import Data.Aeson (FromJSON, ToJSON, eitherDecode, encode)
import qualified Data.ByteString.Char8 as BS8
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString.Lazy.Char8 as BL8
import Data.Either (isLeft)
import Data.List (find, isInfixOf, sort)
import Data.Maybe (listToMaybe)
import qualified Data.Text as Text
import Data.Time.Calendar (Day (ModifiedJulianDay), addDays, diffDays)
import qualified Hedgehog as Hedgehog
import Hedgehog (Gen, Property, (===), assert, forAll, property)
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import Network.HTTP.Types (RequestHeaders, hContentType, hCookie, methodGet, methodPost, status200, status401, status409)
import Network.Wai (Application, defaultRequest, requestHeaders, requestMethod)
import Network.Wai.Test (SRequest (..), SResponse, Session, runSession, setPath, simpleBody, simpleHeaders, simpleStatus, srequest)
import ReactiveEnglish.App (application, closeAppEnv, newAppEnv)
import ReactiveEnglish.Auth
  ( GoogleCredentialFailure (..),
    GoogleEmailVerifiedWire (..),
    GoogleTokenClaims (..),
    GoogleTokenInfo (..),
    normalizeGoogleEmailVerified,
    normalizeGoogleTokenInfo,
    validateGoogleTokenClaims,
  )
import ReactiveEnglish.Config (AppConfig (..), defaultAppConfig)
import qualified ReactiveEnglish.Domain.Rules as Rules
import qualified ReactiveEnglish.Domain.Placement as Placement
import qualified ReactiveEnglish.Domain.Vocabulary as Vocabulary
import ReactiveEnglish.Schema.Generated
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec

main :: IO ()
main =
  hspec $ do
    describe "Reactive English backend" $ do
      it "serves static assets and rejects study API calls without a session" $
        withTestApplication $ \app -> do
          rootResponse <- runSession (get "/") app
          simpleStatus rootResponse `shouldBe` status200
          simpleBody rootResponse `shouldSatisfy` (isInfixOf "Reactive English Test Frontend" . BL8.unpack)

          assetResponse <- runSession (get "/app.js") app
          simpleStatus assetResponse `shouldBe` status200
          simpleBody assetResponse `shouldSatisfy` (isInfixOf "frontend smoke test" . BL8.unpack)

          sessionSnapshot <- decodeResponse =<< runSession (get "/api/session") app
          viewer sessionSnapshot `shouldBe` Nothing

          bootstrapResponse <- runSession (get "/api/bootstrap") app
          simpleStatus bootstrapResponse `shouldBe` status401

      it "creates a dev session, restores it, and exposes a protected bootstrap" $
        withTestApplication $ \app -> do
          (cookieHeaderValue, sessionSnapshot) <- loginDev app "alex@dev.local"
          viewerEmail <$> viewer sessionSnapshot `shouldBe` Just "alex@dev.local"

          restoredSnapshot <- decodeResponse =<< runSession (getWithCookie "/api/session" cookieHeaderValue) app
          viewerEmail <$> viewer restoredSnapshot `shouldBe` Just "alex@dev.local"

          bootstrap <- decodeResponse =<< runSession (getWithCookie "/api/bootstrap" cookieHeaderValue) app
          bootstrapRecommendedLessonId bootstrap `shouldBe` Just "u1-l1"
          profileCompletedLessons (bootstrapProfile bootstrap) `shouldBe` 0
          profileTotalLessons (bootstrapProfile bootstrap) `shouldBe` 4
          length (units bootstrap) `shouldBe` 3
          fmap unitUnlocked (findUnit "u1" bootstrap) `shouldBe` Just True
          fmap unitUnlocked (findUnit "u2" bootstrap) `shouldBe` Just False
          vocabularyTotalTracked (bootstrapVocabulary bootstrap) `shouldBe` 2
          length (vocabularyReviewQueue (bootstrapVocabulary bootstrap)) `shouldSatisfy` (> 0)
          placementHasCompleted (bootstrapPlacementStatus bootstrap) `shouldBe` False
          placementHighestBand (bootstrapPlacementStatus bootstrap) `shouldBe` Nothing

      it "serves placement questions and jumps a strong learner into C2 with one-time XP" $
        withTestApplication $ \app -> do
          (cookieHeaderValue, _) <- loginDev app "alex@dev.local"

          questions <- decodeResponse =<< runSession (getWithCookie "/api/placement" cookieHeaderValue) app
          length (questions :: [PlacementQuestion]) `shouldBe` 6
          all (not . null . placementQuestionChoices) questions `shouldBe` True

          initialBootstrap <- decodeResponse =<< runSession (getWithCookie "/api/bootstrap" cookieHeaderValue) app
          let initialXp = profileXp (bootstrapProfile initialBootstrap)
              submission =
                PlacementSubmission
                  { answers =
                      [ PlacementAnswer {questionId = "placement-a1-greeting", selectedChoice = Just "Nice to meet you.", answerText = Nothing},
                        PlacementAnswer {questionId = "placement-a2-plan", selectedChoice = Just "I am going to visit my aunt tomorrow.", answerText = Nothing},
                        PlacementAnswer {questionId = "placement-b1-opinion", selectedChoice = Just "I agree to some extent, but the cost worries me.", answerText = Nothing},
                        PlacementAnswer {questionId = "placement-b2-concession", selectedChoice = Just "Although the proposal is ambitious, it is financially realistic.", answerText = Nothing},
                        PlacementAnswer {questionId = "placement-c1-qualification", selectedChoice = Just "The evidence suggests a link, but it does not prove causation.", answerText = Nothing},
                        PlacementAnswer {questionId = "placement-c2-stance", selectedChoice = Just "The wording is ostensibly neutral, but it implies skepticism.", answerText = Nothing}
                      ]
                  }

          result <- decodeResponse =<< runSession (postJsonWithCookie "/api/placement" cookieHeaderValue submission) app
          placementPlacedBand result `shouldBe` "C2"
          placementXpAwarded result `shouldSatisfy` (> 0)
          placementCompletedLessonsDelta result `shouldBe` 3
          placementRecommendedLessonId result `shouldBe` Just "u6-l1"
          profileXp (bootstrapProfile (placementBootstrap result)) `shouldBe` initialXp + placementXpAwarded result
          profileCompletedLessons (bootstrapProfile (placementBootstrap result)) `shouldBe` 3
          placementHasCompleted (bootstrapPlacementStatus (placementBootstrap result)) `shouldBe` True
          placementHighestBand (bootstrapPlacementStatus (placementBootstrap result)) `shouldBe` Just "C2"
          fmap lessonStatusValue (findLesson "u6-l1" (placementBootstrap result)) `shouldBe` Just Available

          repeated <- decodeResponse =<< runSession (postJsonWithCookie "/api/placement" cookieHeaderValue submission) app
          placementPlacedBand repeated `shouldBe` "C2"
          placementXpAwarded repeated `shouldBe` 0
          placementCompletedLessonsDelta repeated `shouldBe` 0

      it "serves vocabulary review prompts and records user-scoped word progress" $
        withTestApplication $ \app -> do
          (alexCookie, _) <- loginDev app "alex@dev.local"
          (jamieCookie, _) <- loginDev app "jamie@dev.local"

          initialBootstrap <- decodeResponse =<< runSession (getWithCookie "/api/bootstrap" alexCookie) app
          let initialXp = profileXp (bootstrapProfile initialBootstrap)

          vocabularyDashboard <- decodeResponse =<< runSession (getWithCookie "/api/vocabulary" alexCookie) app
          vocabularyTotalTracked vocabularyDashboard `shouldBe` 2

          reviewPrompts <- decodeResponse =<< runSession (getWithCookie "/api/vocabulary/review" alexCookie) app
          reviewPrompts `shouldSatisfy` (not . null)
          let prompt = head reviewPrompts
              correctAnswer = head (vocabularyPromptAcceptable prompt)
              submission =
                VocabularyReviewSubmission
                  { reviewId = vocabularyPromptReviewId prompt,
                    lexemeId = vocabularyPromptLexemeId prompt,
                    dimension = vocabularyPromptDimension prompt,
                    answerText =
                      if null (vocabularyPromptChoices prompt)
                        then Just correctAnswer
                        else Nothing,
                    selectedChoice =
                      if null (vocabularyPromptChoices prompt)
                        then Nothing
                        else Just correctAnswer
                  }

          result <- decodeResponse =<< runSession (postJsonWithCookie "/api/vocabulary/review" alexCookie submission) app
          vocabularyFeedbackCorrect (vocabularyResultFeedback result) `shouldBe` True
          vocabularyFeedbackMastery (vocabularyResultFeedback result) `shouldSatisfy` (> 0)
          profileXp (vocabularyResultProfile result) `shouldSatisfy` (> initialXp)

          jamieDashboard <- decodeResponse =<< runSession (getWithCookie "/api/vocabulary" jamieCookie) app
          vocabularyAverageMastery jamieDashboard `shouldBe` 0

      it "completes a lesson, awards progress, and unlocks the next lesson per user" $
        withTestApplication $ \app -> do
          (cookieHeaderValue, _) <- loginDev app "alex@dev.local"

          attemptView <- decodeResponse =<< runSession (postJsonWithCookie "/api/attempts" cookieHeaderValue AttemptStart {lessonId = "u1-l1"}) app
          attemptCurrentIndex attemptView `shouldBe` 0

          progressOne <-
            decodeResponse
              =<< runSession
                ( postJsonWithCookie
                    ("/api/attempts/" <> BS8.pack (attemptIdentifier attemptView) <> "/answer")
                    cookieHeaderValue
                    AnswerSubmission
                      { exerciseId = "u1-l1-e1",
                        answerText = Nothing,
                        selectedChoices = ["Nice to meet you."],
                        booleanAnswer = Nothing
                      }
                )
                app
          progressAnsweredCount progressOne `shouldBe` 1
          fmap feedbackCorrect (progressLastFeedback progressOne) `shouldBe` Just True

          progressTwo <-
            decodeResponse
              =<< runSession
                ( postJsonWithCookie
                    ("/api/attempts/" <> BS8.pack (attemptIdentifier attemptView) <> "/answer")
                    cookieHeaderValue
                    AnswerSubmission
                      { exerciseId = "u1-l1-e2",
                        answerText = Just "are",
                        selectedChoices = [],
                        booleanAnswer = Nothing
                      }
                )
                app
          progressFinished progressTwo `shouldBe` True
          progressCorrectCount progressTwo `shouldBe` 2

          completion <- decodeResponse =<< runSession (postEmptyWithCookie ("/api/attempts/" <> BS8.pack (attemptIdentifier attemptView) <> "/complete") cookieHeaderValue) app
          completionLessonCompleted completion `shouldBe` True
          completionXpAwarded completion `shouldSatisfy` (> 0)
          completionNewlyUnlockedLessonId completion `shouldBe` Just "u1-l2"
          profileCompletedLessons (completionProfile completion) `shouldBe` 1
          profileXp (completionProfile completion) `shouldSatisfy` (> 0)

          bootstrap <- decodeResponse =<< runSession (getWithCookie "/api/bootstrap" cookieHeaderValue) app
          bootstrapRecommendedLessonId bootstrap `shouldBe` Just "u1-l2"
          fmap lessonStatusValue (findLesson "u1-l1" bootstrap) `shouldBe` Just Completed
          fmap lessonStatusValue (findLesson "u1-l2" bootstrap) `shouldBe` Just Available

          nextAttempt <- decodeResponse =<< runSession (postJsonWithCookie "/api/attempts" cookieHeaderValue AttemptStart {lessonId = "u1-l2"}) app
          let canonicalOrderingFragments = ["I", "am", "from", "Osaka"]
              presentedOrderingFragments =
                maybe [] exercisePromptFragments (listToMaybe (attemptExercises nextAttempt))
          sort presentedOrderingFragments `shouldBe` sort canonicalOrderingFragments
          presentedOrderingFragments `shouldNotBe` canonicalOrderingFragments

          restoredNextAttempt <- decodeResponse =<< runSession (postJsonWithCookie "/api/attempts" cookieHeaderValue AttemptStart {lessonId = "u1-l2"}) app
          attemptIdentifier restoredNextAttempt `shouldBe` attemptIdentifier nextAttempt
          maybe [] exercisePromptFragments (listToMaybe (attemptExercises restoredNextAttempt)) `shouldBe` presentedOrderingFragments

          nextProgress <-
            decodeResponse
              =<< runSession
                ( postJsonWithCookie
                    ("/api/attempts/" <> BS8.pack (attemptIdentifier nextAttempt) <> "/answer")
                    cookieHeaderValue
                    AnswerSubmission
                      { exerciseId = "u1-l2-e1",
                        answerText = Nothing,
                        selectedChoices = canonicalOrderingFragments,
                        booleanAnswer = Nothing
                      }
                )
                app
          fmap feedbackCorrect (progressLastFeedback nextProgress) `shouldBe` Just True

      it "keeps failed lessons active and isolates progress between different users" $
        withTestApplication $ \app -> do
          (alexCookie, _) <- loginDev app "alex@dev.local"
          (jamieCookie, _) <- loginDev app "jamie@dev.local"

          lockedResponse <-
            runSession
              (postJsonWithCookie "/api/attempts" alexCookie AttemptStart {lessonId = "u1-l2"})
              app
          simpleStatus lockedResponse `shouldBe` status409

          attemptView <- decodeResponse =<< runSession (postJsonWithCookie "/api/attempts" alexCookie AttemptStart {lessonId = "u1-l1"}) app

          _ <-
            decodeResponse
              =<< runSession
                ( postJsonWithCookie
                    ("/api/attempts/" <> BS8.pack (attemptIdentifier attemptView) <> "/answer")
                    alexCookie
                    AnswerSubmission
                      { exerciseId = "u1-l1-e1",
                        answerText = Nothing,
                        selectedChoices = ["At seven o'clock."],
                        booleanAnswer = Nothing
                      }
                )
                app ::
                  IO AttemptProgress
          _ <-
            decodeResponse
              =<< runSession
                ( postJsonWithCookie
                    ("/api/attempts/" <> BS8.pack (attemptIdentifier attemptView) <> "/answer")
                    alexCookie
                    AnswerSubmission
                      { exerciseId = "u1-l1-e2",
                        answerText = Just "am",
                        selectedChoices = [],
                        booleanAnswer = Nothing
                      }
                )
                app ::
                  IO AttemptProgress

          completion <- decodeResponse =<< runSession (postEmptyWithCookie ("/api/attempts/" <> BS8.pack (attemptIdentifier attemptView) <> "/complete") alexCookie) app
          completionLessonCompleted completion `shouldBe` False
          completionNewlyUnlockedLessonId completion `shouldBe` Nothing

          reviewItems <- decodeResponse =<< runSession (getWithCookie "/api/review" alexCookie) app
          length reviewItems `shouldBe` 2
          map reviewDueLabel reviewItems `shouldBe` ["Due now", "Due now"]

          bootstrap <- decodeResponse =<< runSession (getWithCookie "/api/bootstrap" alexCookie) app
          bootstrapRecommendedLessonId bootstrap `shouldBe` Just "u1-l1"
          statsDueReviews (bootstrapStats bootstrap) `shouldBe` 2
          fmap lessonStatusValue (findLesson "u1-l1" bootstrap) `shouldBe` Just InProgress

          jamieBootstrap <- decodeResponse =<< runSession (getWithCookie "/api/bootstrap" jamieCookie) app
          profileCompletedLessons (bootstrapProfile jamieBootstrap) `shouldBe` 0
          statsDueReviews (bootstrapStats jamieBootstrap) `shouldBe` 0
          bootstrapRecommendedLessonId jamieBootstrap `shouldBe` Just "u1-l1"

      it "decodes and normalizes Google tokeninfo email_verified from bool and string responses" $ do
        decodeAndNormalizeGoogleEmailVerified "true" `shouldBe` Right (Right True)
        decodeAndNormalizeGoogleEmailVerified "false" `shouldBe` Right (Right False)
        decodeAndNormalizeGoogleEmailVerified "\"true\"" `shouldBe` Right (Right True)
        decodeAndNormalizeGoogleEmailVerified "\"false\"" `shouldBe` Right (Right False)
        decodeAndNormalizeGoogleEmailVerified "\"YES\"" `shouldBe` Right (Left GoogleCredentialEmailVerifiedMalformed)
        fmap (normalizeGoogleEmailVerified . tokenEmailVerified) decodeGoogleTokenInfoWithoutEmailVerified
          `shouldBe` Right (Left GoogleCredentialEmailVerifiedMissing)

    describe "Reactive English assurance properties" $ do
      it "keeps mastery percentages inside the closed interval" $
        hedgehogShouldSucceed prop_nextMasteryPercentBounded

      it "normalizes answers idempotently" $
        hedgehogShouldSucceed prop_normalizeAnswerIdempotent

      it "keeps review spacing monotone as mastery rises" $
        hedgehogShouldSucceed prop_reviewHoursMonotone

      it "matches the reference completion model" $
        hedgehogShouldSucceed prop_decideCompletionMatchesSpec

      it "matches the reference lesson recommendation walk" $
        hedgehogShouldSucceed prop_findRecommendedLessonMatchesSpec

      it "matches the lesson status case split" $
        hedgehogShouldSucceed prop_lessonStatusMatchesSpec

      it "chooses the current unit from the same lesson recommendation rule" $
        hedgehogShouldSucceed prop_chooseCurrentUnitMatchesSpec

      it "keeps sane unit percentages inside the closed interval" $
        hedgehogShouldSucceed prop_unitProgressPercentBoundedForSaneUnits

      it "returns zero percentages for non-positive denominators" $
        hedgehogShouldSucceed prop_percentZeroForNonPositiveDenominator

      it "matches the reference streak advancement model" $
        hedgehogShouldSucceed prop_advanceStreakMatchesSpec

      it "keeps answer evaluation counters, mastery, review hours, and XP coherent" $
        hedgehogShouldSucceed prop_evaluateAnswerCoherent

      it "keeps shuffled ordering fragments as a non-lossy permutation" $
        hedgehogShouldSucceed prop_shuffleFragmentsPreservesMultiset

      it "avoids presenting canonical ordering fragments when a visible shuffle is possible" $
        hedgehogShouldSucceed prop_shuffleFragmentsAvoidsOriginalWhenDistinct

      it "only changes Ordering fragment presentation during attempt shuffling" $
        hedgehogShouldSucceed prop_shuffleAttemptOrderingFragmentsPreservesExerciseContract

      it "normalizes Google email_verified wire values against the reference model" $
        hedgehogShouldSucceed prop_normalizeGoogleEmailVerifiedMatchesSpec

      it "rejects malformed Google tokeninfo boundary values" $
        hedgehogShouldSucceed prop_normalizeGoogleTokenInfoRejectsMalformedBoundaryValues

      it "validates Google token claims against the reference model" $
        hedgehogShouldSucceed prop_validateGoogleTokenClaimsMatchesSpec

      it "keeps vocabulary mastery percentages inside the closed interval" $
        hedgehogShouldSucceed prop_vocabularyMasteryBounded

      it "keeps vocabulary review spacing monotone as mastery rises" $
        hedgehogShouldSucceed prop_vocabularyReviewHoursMonotone

      it "keeps vocabulary answer evaluation counters and XP coherent" $
        hedgehogShouldSucceed prop_evaluateVocabularyReviewCoherent

      it "keeps placement percentages bounded for sane inputs" $
        hedgehogShouldSucceed prop_placementScorePercentBounded

      it "keeps placement XP deltas nonnegative" $
        hedgehogShouldSucceed prop_placementXpDeltaNonnegative

      it "selects the highest passed placement band" $
        hedgehogShouldSucceed prop_placementChoosesHighestPassedBand

withTestApplication :: (Application -> IO a) -> IO a
withTestApplication action =
  withSystemTempDirectory "reactive-english-test" $ \tempDir -> do
    let databasePath = tempDir </> "reactive-english.db"
        curriculumPath = tempDir </> "english-a2.json"
        staticDir = tempDir </> "frontend-dist"
    createDirectoryIfMissing True staticDir
    writeFile curriculumPath sampleCurriculum
    writeFile (staticDir </> "index.html") "<!doctype html><html><body>Reactive English Test Frontend</body></html>"
    writeFile (staticDir </> "app.js") "console.log('frontend smoke test');"
    let config =
          defaultAppConfig
            { serverPort = 0,
              databasePath = databasePath,
              curriculumPath = curriculumPath,
              staticDir = staticDir,
              authDevMode = True
            }
    bracket (newAppEnv config) closeAppEnv (action . application)

get :: BS8.ByteString -> Session SResponse
get path = srequest (mkRequest methodGet path [] BL.empty)

getWithCookie :: BS8.ByteString -> BS8.ByteString -> Session SResponse
getWithCookie path cookieHeaderValue = srequest (mkRequest methodGet path [(hCookie, cookieHeaderValue)] BL.empty)

postEmpty :: BS8.ByteString -> Session SResponse
postEmpty path = srequest (mkRequest methodPost path [(hContentType, "application/json")] BL.empty)

postEmptyWithCookie :: BS8.ByteString -> BS8.ByteString -> Session SResponse
postEmptyWithCookie path cookieHeaderValue =
  srequest (mkRequest methodPost path [(hContentType, "application/json"), (hCookie, cookieHeaderValue)] BL.empty)

postJson :: ToJSON body => BS8.ByteString -> body -> Session SResponse
postJson path body = srequest (mkRequest methodPost path [(hContentType, "application/json")] (encode body))

postJsonWithCookie :: ToJSON body => BS8.ByteString -> BS8.ByteString -> body -> Session SResponse
postJsonWithCookie path cookieHeaderValue body =
  srequest (mkRequest methodPost path [(hContentType, "application/json"), (hCookie, cookieHeaderValue)] (encode body))

mkRequest :: BS8.ByteString -> BS8.ByteString -> RequestHeaders -> BL.ByteString -> SRequest
mkRequest method path headers body =
  SRequest
    { simpleRequest =
        setPath
          defaultRequest
            { requestMethod = method,
              requestHeaders = headers
            }
          path,
      simpleRequestBody = body
    }

decodeResponse :: FromJSON value => SResponse -> IO value
decodeResponse response =
  case eitherDecode (simpleBody response) of
    Right value -> pure value
    Left decodeError ->
      expectationFailure
        ( "Failed to decode response body: "
            <> decodeError
            <> "\nBody: "
            <> BL8.unpack (simpleBody response)
        )
        >> fail "unreachable"

decodeAndNormalizeGoogleEmailVerified :: String -> Either String (Either GoogleCredentialFailure Bool)
decodeAndNormalizeGoogleEmailVerified emailVerifiedValue =
  fmap (normalizeGoogleEmailVerified . tokenEmailVerified) (decodeGoogleTokenInfoWithEmailVerified emailVerifiedValue)

decodeGoogleTokenInfoWithEmailVerified :: String -> Either String GoogleTokenInfo
decodeGoogleTokenInfoWithEmailVerified emailVerifiedValue =
  decodeGoogleTokenInfoBody
    [ "  \"email_verified\": " <> emailVerifiedValue <> ","
    ]

decodeGoogleTokenInfoWithoutEmailVerified :: Either String GoogleTokenInfo
decodeGoogleTokenInfoWithoutEmailVerified =
  decodeGoogleTokenInfoBody []

decodeGoogleTokenInfoBody :: [String] -> Either String GoogleTokenInfo
decodeGoogleTokenInfoBody emailVerifiedLines =
  eitherDecode
    ( BL8.pack
        ( unlines
            ( [ "{",
                "  \"aud\": \"client-id\",",
                "  \"iss\": \"accounts.google.com\",",
                "  \"sub\": \"google-user-1\",",
                "  \"email\": \"learner@example.com\","
              ]
                <> emailVerifiedLines
                <> [ "  \"name\": \"Learner\",",
                     "  \"picture\": \"https://example.com/avatar.png\",",
                     "  \"exp\": \"9999999999\"",
                     "}"
                   ]
            )
        )
    )

loginDev :: Application -> String -> IO (BS8.ByteString, SessionSnapshot)
loginDev app emailValue = do
  response <-
    runSession
      (postJson "/api/auth/dev" DevLoginRequest {email = emailValue})
      app
  cookieHeaderValue <-
    case lookup "Set-Cookie" (simpleHeaders response) of
      Just headerValue -> pure (BS8.takeWhile (/= ';') headerValue)
      Nothing -> expectationFailure "Missing Set-Cookie header after dev login" >> fail "unreachable"
  snapshot <- decodeResponse response
  pure (cookieHeaderValue, snapshot)

findUnit :: String -> AppBootstrap -> Maybe UnitSummary
findUnit requestedUnitId AppBootstrap {units} =
  find (\UnitSummary {unitId} -> unitId == requestedUnitId) units

bootstrapProfile :: AppBootstrap -> LearnerProfile
bootstrapProfile AppBootstrap {profile} = profile

bootstrapStats :: AppBootstrap -> DashboardStats
bootstrapStats AppBootstrap {stats} = stats

bootstrapRecommendedLessonId :: AppBootstrap -> Maybe String
bootstrapRecommendedLessonId AppBootstrap {recommendedLessonId} = recommendedLessonId

findLesson :: String -> AppBootstrap -> Maybe LessonSummary
findLesson requestedLessonId AppBootstrap {units} =
  find
    (\LessonSummary {lessonId} -> lessonId == requestedLessonId)
    [ lessonSummary
      | UnitSummary {lessonSummaries} <- units,
        lessonSummary <- lessonSummaries
    ]

profileCompletedLessons :: LearnerProfile -> Int
profileCompletedLessons LearnerProfile {completedLessons} = completedLessons

profileTotalLessons :: LearnerProfile -> Int
profileTotalLessons LearnerProfile {totalLessons} = totalLessons

profileXp :: LearnerProfile -> Int
profileXp LearnerProfile {xp} = xp

unitUnlocked :: UnitSummary -> Bool
unitUnlocked UnitSummary {unlocked} = unlocked

viewerEmail :: UserSummary -> String
viewerEmail UserSummary {email} = email

lessonDetailExercises :: LessonDetail -> [ExercisePrompt]
lessonDetailExercises LessonDetail {exercises} = exercises

attemptCurrentIndex :: AttemptView -> Int
attemptCurrentIndex AttemptView {currentIndex} = currentIndex

attemptIdentifier :: AttemptView -> String
attemptIdentifier AttemptView {attemptId} = attemptId

attemptExercises :: AttemptView -> [ExercisePrompt]
attemptExercises AttemptView {exercises} = exercises

progressAnsweredCount :: AttemptProgress -> Int
progressAnsweredCount AttemptProgress {answeredCount} = answeredCount

progressCorrectCount :: AttemptProgress -> Int
progressCorrectCount AttemptProgress {correctCount} = correctCount

progressLastFeedback :: AttemptProgress -> Maybe AnswerFeedback
progressLastFeedback AttemptProgress {lastFeedback} = lastFeedback

progressFinished :: AttemptProgress -> Bool
progressFinished AttemptProgress {finished} = finished

feedbackCorrect :: AnswerFeedback -> Bool
feedbackCorrect AnswerFeedback {correct} = correct

completionLessonCompleted :: AttemptCompletion -> Bool
completionLessonCompleted AttemptCompletion {lessonCompleted} = lessonCompleted

completionXpAwarded :: AttemptCompletion -> Int
completionXpAwarded AttemptCompletion {xpAwarded} = xpAwarded

completionNewlyUnlockedLessonId :: AttemptCompletion -> Maybe String
completionNewlyUnlockedLessonId AttemptCompletion {newlyUnlockedLessonId} = newlyUnlockedLessonId

completionProfile :: AttemptCompletion -> LearnerProfile
completionProfile AttemptCompletion {profile} = profile

reviewDueLabel :: ReviewSummary -> String
reviewDueLabel ReviewSummary {dueLabel} = dueLabel

bootstrapVocabulary :: AppBootstrap -> VocabularyDashboard
bootstrapVocabulary AppBootstrap {vocabulary} = vocabulary

bootstrapPlacementStatus :: AppBootstrap -> PlacementStatus
bootstrapPlacementStatus AppBootstrap {placementStatus} = placementStatus

placementHasCompleted :: PlacementStatus -> Bool
placementHasCompleted PlacementStatus {hasCompletedPlacement} = hasCompletedPlacement

placementHighestBand :: PlacementStatus -> Maybe String
placementHighestBand PlacementStatus {highestCefrBand} = highestCefrBand

vocabularyTotalTracked :: VocabularyDashboard -> Int
vocabularyTotalTracked VocabularyDashboard {totalTracked} = totalTracked

vocabularyAverageMastery :: VocabularyDashboard -> Int
vocabularyAverageMastery VocabularyDashboard {averageMasteryPercent} = averageMasteryPercent

vocabularyReviewQueue :: VocabularyDashboard -> [VocabularyReviewPrompt]
vocabularyReviewQueue VocabularyDashboard {reviewQueue} = reviewQueue

vocabularyPromptReviewId :: VocabularyReviewPrompt -> String
vocabularyPromptReviewId VocabularyReviewPrompt {reviewId} = reviewId

vocabularyPromptLexemeId :: VocabularyReviewPrompt -> String
vocabularyPromptLexemeId VocabularyReviewPrompt {lexemeId} = lexemeId

vocabularyPromptDimension :: VocabularyReviewPrompt -> KnowledgeDimension
vocabularyPromptDimension VocabularyReviewPrompt {dimension} = dimension

vocabularyPromptChoices :: VocabularyReviewPrompt -> [String]
vocabularyPromptChoices VocabularyReviewPrompt {choices} = choices

vocabularyPromptAcceptable :: VocabularyReviewPrompt -> [String]
vocabularyPromptAcceptable VocabularyReviewPrompt {acceptableAnswers} = acceptableAnswers

vocabularyResultFeedback :: VocabularyReviewResult -> VocabularyFeedback
vocabularyResultFeedback VocabularyReviewResult {feedback} = feedback

vocabularyResultProfile :: VocabularyReviewResult -> LearnerProfile
vocabularyResultProfile VocabularyReviewResult {profile} = profile

vocabularyFeedbackCorrect :: VocabularyFeedback -> Bool
vocabularyFeedbackCorrect VocabularyFeedback {correct} = correct

vocabularyFeedbackMastery :: VocabularyFeedback -> Int
vocabularyFeedbackMastery VocabularyFeedback {masteryPercent} = masteryPercent

placementQuestionChoices :: PlacementQuestion -> [String]
placementQuestionChoices PlacementQuestion {choices} = choices

placementPlacedBand :: PlacementResult -> String
placementPlacedBand PlacementResult {placedCefrBand} = placedCefrBand

placementXpAwarded :: PlacementResult -> Int
placementXpAwarded PlacementResult {xpAwarded} = xpAwarded

placementCompletedLessonsDelta :: PlacementResult -> Int
placementCompletedLessonsDelta PlacementResult {completedLessonsDelta} = completedLessonsDelta

placementRecommendedLessonId :: PlacementResult -> Maybe String
placementRecommendedLessonId PlacementResult {recommendedLessonId} = recommendedLessonId

placementBootstrap :: PlacementResult -> AppBootstrap
placementBootstrap PlacementResult {bootstrap} = bootstrap

lessonStatusValue :: LessonSummary -> LessonStatus
lessonStatusValue LessonSummary {status} = status

statsDueReviews :: DashboardStats -> Int
statsDueReviews DashboardStats {dueReviews} = dueReviews

exercisePromptFragments :: ExercisePrompt -> [String]
exercisePromptFragments ExercisePrompt {fragments} = fragments

exercisePromptKind :: ExercisePrompt -> ExerciseKind
exercisePromptKind ExercisePrompt {kind} = kind

exercisePromptAcceptableAnswers :: ExercisePrompt -> [String]
exercisePromptAcceptableAnswers ExercisePrompt {acceptableAnswers} = acceptableAnswers

sampleCurriculum :: String
sampleCurriculum =
  unlines
    [ "{",
      "  \"lexemes\": [",
      "    {",
      "      \"lexemeId\": \"lex-nice-to-meet-you\",",
      "      \"headword\": \"Nice to meet you\",",
      "      \"partOfSpeech\": \"phrase\",",
      "      \"cefrBand\": \"A1\",",
      "      \"lessonId\": \"u1-l1\",",
      "      \"definition\": \"A polite phrase for a first meeting.\",",
      "      \"exampleSentence\": \"Nice to meet you, Yuki.\",",
      "      \"translation\": \"first meeting greeting\",",
      "      \"collocations\": [\"Nice to meet you too\", \"It is nice to meet you\"],",
      "      \"distractors\": [\"At seven\", \"From Osaka\", \"Good night\"],",
      "      \"confusables\": [\"Nice to watch you\", \"Meet to nice you\"],",
      "      \"tags\": [\"greeting\", \"social\"]",
      "    },",
      "    {",
      "      \"lexemeId\": \"lex-from\",",
      "      \"headword\": \"from\",",
      "      \"partOfSpeech\": \"preposition\",",
      "      \"cefrBand\": \"A1\",",
      "      \"lessonId\": \"u1-l2\",",
      "      \"definition\": \"A word used to say origin.\",",
      "      \"exampleSentence\": \"I am from Osaka.\",",
      "      \"translation\": \"origin word\",",
      "      \"collocations\": [\"from Osaka\", \"from school\"],",
      "      \"distractors\": [\"for\", \"at\", \"with\"],",
      "      \"confusables\": [\"for Osaka\", \"at school\"],",
      "      \"tags\": [\"origin\", \"preposition\"]",
      "    }",
      "  ],",
      "  \"placementQuestions\": [",
      "    {",
      "      \"questionId\": \"placement-a1-greeting\",",
      "      \"cefrBand\": \"A1\",",
      "      \"skill\": \"social language\",",
      "      \"prompt\": \"Choose the best reply to: Hi, I'm Yuki.\",",
      "      \"promptDetail\": null,",
      "      \"choices\": [\"Nice to meet you.\", \"At seven o'clock.\", \"She goes by train.\"],",
      "      \"acceptableAnswers\": [\"Nice to meet you.\"],",
      "      \"explanation\": \"Nice to meet you is a standard first-meeting reply.\"",
      "    },",
      "    {",
      "      \"questionId\": \"placement-a2-plan\",",
      "      \"cefrBand\": \"A2\",",
      "      \"skill\": \"future plans\",",
      "      \"prompt\": \"Choose the sentence that clearly describes a plan.\",",
      "      \"promptDetail\": null,",
      "      \"choices\": [\"I am going to visit my aunt tomorrow.\", \"Visit aunt I tomorrow.\", \"I visited usually.\"],",
      "      \"acceptableAnswers\": [\"I am going to visit my aunt tomorrow.\"],",
      "      \"explanation\": \"Going to expresses a planned future action.\"",
      "    },",
      "    {",
      "      \"questionId\": \"placement-b1-opinion\",",
      "      \"cefrBand\": \"B1\",",
      "      \"skill\": \"opinions\",",
      "      \"prompt\": \"Choose the balanced opinion.\",",
      "      \"promptDetail\": null,",
      "      \"choices\": [\"I agree to some extent, but the cost worries me.\", \"Everything is perfect always.\", \"No opinion because yes.\"],",
      "      \"acceptableAnswers\": [\"I agree to some extent, but the cost worries me.\"],",
      "      \"explanation\": \"The sentence gives a view and a reservation.\"",
      "    },",
      "    {",
      "      \"questionId\": \"placement-b2-concession\",",
      "      \"cefrBand\": \"B2\",",
      "      \"skill\": \"concession\",",
      "      \"prompt\": \"Choose the best concession sentence.\",",
      "      \"promptDetail\": null,",
      "      \"choices\": [\"Although the proposal is ambitious, it is financially realistic.\", \"Because the proposal ambitious realistic.\", \"It is realistic although because.\"],",
      "      \"acceptableAnswers\": [\"Although the proposal is ambitious, it is financially realistic.\"],",
      "      \"explanation\": \"Although introduces a concession before the main claim.\"",
      "    },",
      "    {",
      "      \"questionId\": \"placement-c1-qualification\",",
      "      \"cefrBand\": \"C1\",",
      "      \"skill\": \"argument precision\",",
      "      \"prompt\": \"Choose the most cautious interpretation of evidence.\",",
      "      \"promptDetail\": null,",
      "      \"choices\": [\"The evidence suggests a link, but it does not prove causation.\", \"The evidence proves every possible cause.\", \"The evidence is not evidence.\"],",
      "      \"acceptableAnswers\": [\"The evidence suggests a link, but it does not prove causation.\"],",
      "      \"explanation\": \"The sentence separates suggestion from proof.\"",
      "    },",
      "    {",
      "      \"questionId\": \"placement-c2-stance\",",
      "      \"cefrBand\": \"C2\",",
      "      \"skill\": \"implied stance\",",
      "      \"prompt\": \"Choose the sentence with subtle stance and implication.\",",
      "      \"promptDetail\": null,",
      "      \"choices\": [\"The wording is ostensibly neutral, but it implies skepticism.\", \"The words are good and very nice.\", \"Neutral words are neutral because neutral.\"],",
      "      \"acceptableAnswers\": [\"The wording is ostensibly neutral, but it implies skepticism.\"],",
      "      \"explanation\": \"Ostensibly signals appearance with possible doubt.\"",
      "    }",
      "  ],",
      "  \"units\": [",
      "    {",
      "      \"unitId\": \"u1\",",
      "      \"index\": 1,",
      "      \"title\": \"Introductions\",",
      "      \"cefrBand\": \"A1\",",
      "      \"focus\": \"Greetings and basic be-verbs\",",
      "      \"lessons\": [",
      "        {",
      "          \"lessonId\": \"u1-l1\",",
      "          \"index\": 1,",
      "          \"title\": \"Hello There\",",
      "          \"subtitle\": \"Names and introductions\",",
      "          \"goal\": \"Introduce yourself and ask for basic personal details.\",",
      "          \"xpReward\": 40,",
      "          \"narrative\": \"Start with a quick exchange between two new classmates.\",",
      "          \"tips\": [\"Keep be-verbs aligned with the subject.\", \"Short introductions usually end with a greeting.\"],",
      "          \"exercises\": [",
      "            {",
      "              \"exerciseId\": \"u1-l1-e1\",",
      "              \"kind\": \"MultipleChoice\",",
      "              \"prompt\": \"Choose the best reply.\",",
      "              \"promptDetail\": \"A: Hi, I'm Yuki. ____\",",
      "              \"choices\": [\"Nice to meet you.\", \"I am from Tokyo.\", \"At seven o'clock.\"],",
      "              \"fragments\": [],",
      "              \"answerText\": null,",
      "              \"acceptableAnswers\": [\"Nice to meet you.\"],",
      "              \"translation\": \"はじめまして。\",",
      "              \"hint\": \"Think about introductions.\",",
      "              \"explanation\": \"This is the usual reply when someone introduces themselves.\"",
      "            },",
      "            {",
      "              \"exerciseId\": \"u1-l1-e2\",",
      "              \"kind\": \"Cloze\",",
      "              \"prompt\": \"Fill in the missing verb.\",",
      "              \"promptDetail\": \"We ____ classmates.\",",
      "              \"choices\": [],",
      "              \"fragments\": [],",
      "              \"answerText\": \"are\",",
      "              \"acceptableAnswers\": [\"are\"],",
      "              \"translation\": \"私たちはクラスメートです。\",",
      "              \"hint\": \"Use the be-verb for we.\",",
      "              \"explanation\": \"The subject we takes are.\"",
      "            }",
      "          ]",
      "        },",
      "        {",
      "          \"lessonId\": \"u1-l2\",",
      "          \"index\": 2,",
      "          \"title\": \"Where Are You From?\",",
      "          \"subtitle\": \"Countries and hometowns\",",
      "          \"goal\": \"Ask and answer simple origin questions.\",",
      "          \"xpReward\": 45,",
      "          \"narrative\": \"Move from names to hometowns and countries.\",",
      "          \"tips\": [\"Use from after be-verbs for origin.\"],",
      "          \"exercises\": [",
      "            {",
      "              \"exerciseId\": \"u1-l2-e1\",",
      "              \"kind\": \"Ordering\",",
      "              \"prompt\": \"Build the sentence.\",",
      "              \"promptDetail\": null,",
      "              \"choices\": [],",
      "              \"fragments\": [\"I\", \"am\", \"from\", \"Osaka\"],",
      "              \"answerText\": null,",
      "              \"acceptableAnswers\": [\"I am from Osaka\"],",
      "              \"translation\": \"私は大阪出身です。\",",
      "              \"hint\": \"Start with the subject.\",",
      "              \"explanation\": \"The natural sentence order is subject + be + from + place.\"",
      "            }",
      "          ]",
      "        }",
      "      ]",
      "    },",
      "    {",
      "      \"unitId\": \"u2\",",
      "      \"index\": 2,",
      "      \"title\": \"Daily Routines\",",
      "      \"cefrBand\": \"A2\",",
      "      \"focus\": \"Simple present and time expressions\",",
      "      \"lessons\": [",
      "        {",
      "          \"lessonId\": \"u2-l1\",",
      "          \"index\": 1,",
      "          \"title\": \"Morning Habits\",",
      "          \"subtitle\": \"Simple present basics\",",
      "          \"goal\": \"Describe short daily routines.\",",
      "          \"xpReward\": 50,",
      "          \"narrative\": \"Shift from introductions into ordinary daily life.\",",
      "          \"tips\": [\"Third-person singular takes -s.\"],",
      "          \"exercises\": [",
      "            {",
      "              \"exerciseId\": \"u2-l1-e1\",",
      "              \"kind\": \"TrueFalse\",",
      "              \"prompt\": \"Decide if the sentence is correct.\",",
      "              \"promptDetail\": \"She go to work at eight.\",",
      "              \"choices\": [\"true\", \"false\"],",
      "              \"fragments\": [],",
      "              \"answerText\": null,",
      "              \"acceptableAnswers\": [\"false\"],",
      "              \"translation\": \"彼女は8時に仕事へ行く。\",",
      "              \"hint\": \"Check the verb ending.\",",
      "              \"explanation\": \"Third-person singular needs goes, so the sentence is false.\"",
      "            }",
      "          ]",
      "        }",
      "      ]",
      "    },",
      "    {",
      "      \"unitId\": \"u6\",",
      "      \"index\": 3,",
      "      \"title\": \"Implied Stance\",",
      "      \"cefrBand\": \"C2\",",
      "      \"focus\": \"Subtle tone and rhetorical implication\",",
      "      \"lessons\": [",
      "        {",
      "          \"lessonId\": \"u6-l1\",",
      "          \"index\": 1,",
      "          \"title\": \"Reading Between The Lines\",",
      "          \"subtitle\": \"stance and implication\",",
      "          \"goal\": \"Identify implied attitude in precise formal language.\",",
      "          \"xpReward\": 90,",
      "          \"narrative\": \"Advanced readers separate literal meaning from implied stance.\",",
      "          \"tips\": [\"Notice words such as ostensibly and supposedly.\", \"Base interpretation on specific wording.\"],",
      "          \"exercises\": [",
      "            {",
      "              \"exerciseId\": \"u6-l1-e1\",",
      "              \"kind\": \"MultipleChoice\",",
      "              \"prompt\": \"What does ostensibly suggest?\",",
      "              \"promptDetail\": \"The solution is ostensibly simple, but the consequences are unclear.\",",
      "              \"choices\": [\"It appears simple but may not be.\", \"It is certainly simple.\", \"It is illegal.\"],",
      "              \"fragments\": [],",
      "              \"answerText\": null,",
      "              \"acceptableAnswers\": [\"It appears simple but may not be.\"],",
      "              \"translation\": null,",
      "              \"hint\": \"Think appearance versus reality.\",",
      "              \"explanation\": \"Ostensibly often suggests a gap between appearance and reality.\"",
      "            }",
      "          ]",
      "        }",
      "      ]",
      "    }",
      "  ]",
      "}"
    ]

hedgehogShouldSucceed :: Property -> IO ()
hedgehogShouldSucceed propertyCheck = do
  ok <- Hedgehog.check propertyCheck
  ok `shouldBe` True

prop_nextMasteryPercentBounded :: Property
prop_nextMasteryPercentBounded =
  property $ do
    mastery <- forAll (Gen.int (Range.linear (-200) 300))
    correct <- forAll Gen.bool
    let updated = Rules.nextMasteryPercent mastery correct
    assert (updated >= 0 && updated <= 100)

prop_normalizeAnswerIdempotent :: Property
prop_normalizeAnswerIdempotent =
  property $ do
    raw <- forAll genAnswerText
    Rules.normalizeAnswer (Rules.normalizeAnswer raw) === Rules.normalizeAnswer raw

prop_reviewHoursMonotone :: Property
prop_reviewHoursMonotone =
  property $ do
    left <- forAll (Gen.int (Range.linear (-50) 150))
    right <- forAll (Gen.int (Range.linear (-50) 150))
    let lower = min left right
        upper = max left right
    assert (Rules.reviewHoursForMastery lower <= Rules.reviewHoursForMastery upper)

prop_decideCompletionMatchesSpec :: Property
prop_decideCompletionMatchesSpec =
  property $ do
    alreadyCompleted <- forAll Gen.bool
    previousBestAccuracy <- forAll (Gen.int (Range.linear 0 100))
    accuracyPercent <- forAll (Gen.int (Range.linear 0 100))
    correctCount <- forAll (Gen.int (Range.linear 0 40))
    totalExercises <- forAll (Gen.int (Range.linear 0 40))
    lessonXpReward <- forAll (Gen.int (Range.linear 0 200))
    Rules.decideCompletion alreadyCompleted previousBestAccuracy accuracyPercent correctCount totalExercises lessonXpReward
      === specDecideCompletion alreadyCompleted previousBestAccuracy accuracyPercent correctCount totalExercises lessonXpReward

prop_findRecommendedLessonMatchesSpec :: Property
prop_findRecommendedLessonMatchesSpec =
  property $ do
    unitsValue <- forAll (Gen.list (Range.linear 0 5) genUnitSummary)
    Rules.findRecommendedLessonId unitsValue === specFindRecommendedLessonId unitsValue

prop_lessonStatusMatchesSpec :: Property
prop_lessonStatusMatchesSpec =
  property $ do
    recommended <- forAll (Gen.maybe genLessonId)
    lessonIdValue <- forAll genLessonId
    completed <- forAll Gen.bool
    attemptCount <- forAll (Gen.int (Range.linear 0 10))
    Rules.lessonStatusFrom recommended lessonIdValue completed attemptCount
      === specLessonStatusFrom recommended lessonIdValue completed attemptCount

prop_chooseCurrentUnitMatchesSpec :: Property
prop_chooseCurrentUnitMatchesSpec =
  property $ do
    unitsValue <- forAll (Gen.list (Range.linear 0 5) genUnitSummary)
    recommended <- forAll (Gen.maybe genLessonId)
    fmap (\UnitSummary {unitId} -> unitId) (Rules.chooseCurrentUnit recommended unitsValue)
      === fmap (\UnitSummary {unitId} -> unitId) (specChooseCurrentUnit recommended unitsValue)

prop_unitProgressPercentBoundedForSaneUnits :: Property
prop_unitProgressPercentBoundedForSaneUnits =
  property $ do
    total <- forAll (Gen.int (Range.linear 0 200))
    completed <- forAll (Gen.int (Range.linear 0 total))
    let unit = minimalUnitSummary completed total
        progress = Rules.unitProgressPercent unit
    assert (progress >= 0 && progress <= 100)

prop_percentZeroForNonPositiveDenominator :: Property
prop_percentZeroForNonPositiveDenominator =
  property $ do
    numerator <- forAll (Gen.int (Range.linear (-500) 500))
    denominator <- forAll (Gen.int (Range.linear (-500) 0))
    Rules.percent numerator denominator === 0

prop_advanceStreakMatchesSpec :: Property
prop_advanceStreakMatchesSpec =
  property $ do
    today <- forAll genDay
    currentStreak <- forAll (Gen.int (Range.linear (-10) 200))
    lastActive <- forAll (genLastActiveDay today)
    Rules.advanceStreak today currentStreak lastActive === specAdvanceStreak today currentStreak lastActive

prop_evaluateAnswerCoherent :: Property
prop_evaluateAnswerCoherent =
  property $ do
    priorMastery <- forAll (Gen.int (Range.linear (-50) 150))
    priorCorrect <- forAll (Gen.int (Range.linear 0 50))
    priorIncorrect <- forAll (Gen.int (Range.linear 0 50))
    shouldSubmitCorrect <- forAll Gen.bool
    let exercise = sampleChoiceExercise
        submission =
          AnswerSubmission
            { exerciseId = "sample-choice"
            , answerText = Nothing
            , selectedChoices = [if shouldSubmitCorrect then "Nice to meet you." else "At seven."]
            , booleanAnswer = Nothing
            }
        evaluation = Rules.evaluateAnswer exercise submission priorMastery priorCorrect priorIncorrect
    Rules.evaluationCorrect evaluation === shouldSubmitCorrect
    Rules.evaluationCorrectCount evaluation === priorCorrect + if shouldSubmitCorrect then 1 else 0
    Rules.evaluationIncorrectCount evaluation === priorIncorrect + if shouldSubmitCorrect then 0 else 1
    Rules.evaluationMasteryPercent evaluation === Rules.nextMasteryPercent priorMastery shouldSubmitCorrect
    Rules.evaluationXpDelta evaluation === if shouldSubmitCorrect then 5 else 0
    Rules.evaluationNextReviewHours evaluation
      === if shouldSubmitCorrect then Rules.reviewHoursForMastery (Rules.evaluationMasteryPercent evaluation) else 0

prop_shuffleFragmentsPreservesMultiset :: Property
prop_shuffleFragmentsPreservesMultiset =
  property $ do
    seed <- forAll genShuffleSeed
    fragments <- forAll (Gen.list (Range.linear 0 12) genFragment)
    let shuffled = Rules.shuffleFragmentsWithSeed seed fragments
    length shuffled === length fragments
    sort shuffled === sort fragments

prop_shuffleFragmentsAvoidsOriginalWhenDistinct :: Property
prop_shuffleFragmentsAvoidsOriginalWhenDistinct =
  property $ do
    seed <- forAll genShuffleSeed
    firstFragment <- forAll genFragment
    secondFragment <- forAll (Gen.filter (/= firstFragment) genFragment)
    remainingFragments <- forAll (Gen.list (Range.linear 0 8) genFragment)
    let fragments = firstFragment : secondFragment : remainingFragments
        shuffled = Rules.shuffleFragmentsWithSeed seed fragments
    assert (shuffled /= fragments)
    sort shuffled === sort fragments

prop_shuffleAttemptOrderingFragmentsPreservesExerciseContract :: Property
prop_shuffleAttemptOrderingFragmentsPreservesExerciseContract =
  property $ do
    seed <- forAll genShuffleSeed
    fragments <- forAll (Gen.list (Range.linear 2 10) genFragment)
    let orderingExercise = sampleOrderingExercise fragments
        shuffledExercises = Rules.shuffleAttemptOrderingFragments seed [sampleChoiceExercise, orderingExercise]
    case shuffledExercises of
      [choiceExercise, shuffledOrderingExercise] -> do
        choiceExercise === sampleChoiceExercise
        exercisePromptKind shuffledOrderingExercise === Ordering
        sort (exercisePromptFragments shuffledOrderingExercise) === sort fragments
        exercisePromptAcceptableAnswers shuffledOrderingExercise === exercisePromptAcceptableAnswers orderingExercise
      _ ->
        assert False

prop_normalizeGoogleEmailVerifiedMatchesSpec :: Property
prop_normalizeGoogleEmailVerifiedMatchesSpec =
  property $ do
    wireValue <- forAll genMaybeGoogleEmailVerifiedWire
    normalizeGoogleEmailVerified wireValue === specNormalizeGoogleEmailVerified wireValue

prop_validateGoogleTokenClaimsMatchesSpec :: Property
prop_validateGoogleTokenClaimsMatchesSpec =
  property $ do
    clientId <- forAll genClientId
    claims <- forAll (genGoogleTokenClaims clientId)
    now <- forAll (Gen.integral (Range.linear 0 2_000_000_000))
    validateGoogleTokenClaims clientId now claims === specValidateGoogleTokenClaims clientId now claims

prop_normalizeGoogleTokenInfoRejectsMalformedBoundaryValues :: Property
prop_normalizeGoogleTokenInfoRejectsMalformedBoundaryValues =
  property $ do
    malformedEmailVerified <- forAll (Gen.element ["", "yes", "1", "verified", "no"])
    let tokenInfo =
          sampleGoogleTokenInfo
            { tokenEmailVerified = Just (GoogleEmailVerifiedString (Text.pack malformedEmailVerified))
            }
    assert (isLeft (normalizeGoogleTokenInfo tokenInfo))

prop_vocabularyMasteryBounded :: Property
prop_vocabularyMasteryBounded =
  property $ do
    mastery <- forAll (Gen.int (Range.linear (-200) 300))
    correct <- forAll Gen.bool
    let updated = Vocabulary.nextVocabularyMasteryPercent mastery correct
    assert (updated >= 0 && updated <= 100)

prop_vocabularyReviewHoursMonotone :: Property
prop_vocabularyReviewHoursMonotone =
  property $ do
    left <- forAll (Gen.int (Range.linear (-50) 150))
    right <- forAll (Gen.int (Range.linear (-50) 150))
    let lower = min left right
        upper = max left right
    assert (Vocabulary.vocabularyReviewHours lower <= Vocabulary.vocabularyReviewHours upper)

prop_evaluateVocabularyReviewCoherent :: Property
prop_evaluateVocabularyReviewCoherent =
  property $ do
    dimension <- forAll Gen.enumBounded
    priorMastery <- forAll (Gen.int (Range.linear (-50) 150))
    priorCorrect <- forAll (Gen.int (Range.linear 0 50))
    priorIncorrect <- forAll (Gen.int (Range.linear 0 50))
    shouldSubmitCorrect <- forAll Gen.bool
    let expected = "routine"
        submitted = if shouldSubmitCorrect then "routine" else "ticket"
        evaluation =
          Vocabulary.evaluateVocabularyReview
            dimension
            [expected]
            (Just submitted)
            Nothing
            priorMastery
            priorCorrect
            priorIncorrect
    Vocabulary.evaluationCorrect evaluation === shouldSubmitCorrect
    Vocabulary.evaluationCorrectCount evaluation === priorCorrect + if shouldSubmitCorrect then 1 else 0
    Vocabulary.evaluationIncorrectCount evaluation === priorIncorrect + if shouldSubmitCorrect then 0 else 1
    Vocabulary.evaluationMasteryPercent evaluation === Vocabulary.nextVocabularyMasteryPercent priorMastery shouldSubmitCorrect
    Vocabulary.evaluationXpDelta evaluation === if shouldSubmitCorrect then Vocabulary.dimensionXpDelta dimension else 0
    Vocabulary.evaluationNextReviewHours evaluation
      === if shouldSubmitCorrect then Vocabulary.vocabularyReviewHours (Vocabulary.evaluationMasteryPercent evaluation) else 0

prop_placementScorePercentBounded :: Property
prop_placementScorePercentBounded =
  property $ do
    total <- forAll (Gen.int (Range.linear 0 200))
    correct <- forAll (Gen.int (Range.linear 0 total))
    let score = Placement.placementScorePercent correct total
    assert (score >= 0 && score <= 100)

prop_placementXpDeltaNonnegative :: Property
prop_placementXpDeltaNonnegative =
  property $ do
    previous <- forAll (Gen.maybe genPlacementLevel)
    next <- forAll genPlacementLevel
    assert (Placement.placementXpDelta previous next >= 0)
    case previous of
      Just previousLevel | Placement.levelRank previousLevel >= Placement.levelRank next ->
        Placement.placementXpDelta previous next === 0
      _ ->
        assert True

prop_placementChoosesHighestPassedBand :: Property
prop_placementChoosesHighestPassedBand =
  property $ do
    target <- forAll genPlacementLevel
    let scores =
          [ ( level,
              if Placement.levelRank level <= Placement.levelRank target then 2 else 1,
              3
            )
            | level <- Placement.allCefrLevels
          ]
    Placement.placementLevelFromBandScores scores === target

specDecideCompletion :: Bool -> Int -> Int -> Int -> Int -> Int -> Rules.CompletionDecision
specDecideCompletion alreadyCompleted previousBestAccuracy accuracyPercent correctCount totalExercises lessonXpReward =
  let specPassingAttempt = accuracyPercent >= 60
      specLessonCompleted = alreadyCompleted || specPassingAttempt
      specNewlyCompleted = not alreadyCompleted && specPassingAttempt
      specBestAccuracy = max accuracyPercent previousBestAccuracy
      specXpAwarded =
        (correctCount * 5)
          + (lessonXpReward * correctCount `div` max 1 totalExercises)
   in Rules.CompletionDecision
        { Rules.completionAccuracyPercent = accuracyPercent
        , Rules.completionPassingAttempt = specPassingAttempt
        , Rules.completionLessonCompleted = specLessonCompleted
        , Rules.completionNewlyCompleted = specNewlyCompleted
        , Rules.completionBestAccuracy = specBestAccuracy
        , Rules.completionXpAwarded = specXpAwarded
        }

specFindRecommendedLessonId :: [UnitSummary] -> Maybe String
specFindRecommendedLessonId unitsValue =
  listToMaybe
    [ lessonId
    | UnitSummary {lessonSummaries} <- unitsValue
    , LessonSummary {lessonId, status} <- lessonSummaries
    , status /= Completed
    ]

specLessonStatusFrom :: Maybe String -> String -> Bool -> Int -> LessonStatus
specLessonStatusFrom recommended lessonIdValue completed attemptCount
  | completed = Completed
  | Just lessonIdValue == recommended && attemptCount > 0 = InProgress
  | Just lessonIdValue == recommended = Available
  | otherwise = Locked

specChooseCurrentUnit :: Maybe String -> [UnitSummary] -> Maybe UnitSummary
specChooseCurrentUnit recommended unitsValue =
  case recommended of
    Just lessonIdValue ->
      find
        (\UnitSummary {lessonSummaries} ->
          any (\LessonSummary {lessonId} -> lessonId == lessonIdValue) lessonSummaries
        )
        unitsValue
    Nothing ->
      case reverse unitsValue of
        currentUnit : _ -> Just currentUnit
        [] -> Nothing

specAdvanceStreak :: Day -> Int -> Maybe String -> Int
specAdvanceStreak today currentStreak maybeLastActiveDay =
  case maybeLastActiveDay >>= Rules.parseDay of
    Nothing -> 1
    Just lastActiveDay
      | lastActiveDay == today -> max 1 currentStreak
      | diffDays today lastActiveDay == 1 -> max 1 currentStreak + 1
      | otherwise -> 1

specNormalizeGoogleEmailVerified :: Maybe GoogleEmailVerifiedWire -> Either GoogleCredentialFailure Bool
specNormalizeGoogleEmailVerified maybeWireValue =
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

specValidateGoogleTokenClaims :: String -> Integer -> GoogleTokenClaims -> Either GoogleCredentialFailure ()
specValidateGoogleTokenClaims clientId now GoogleTokenClaims {claimAud, claimIss, claimEmailVerified, claimExp}
  | not (specGoogleIssuerIsValid claimIss) = Left GoogleCredentialIssuerInvalid
  | claimAud /= clientId = Left GoogleCredentialAudienceMismatch
  | not (specGoogleExpiryIsValid now claimExp) = Left GoogleCredentialExpired
  | not claimEmailVerified = Left GoogleCredentialEmailNotVerified
  | otherwise = Right ()

specGoogleIssuerIsValid :: String -> Bool
specGoogleIssuerIsValid issuerValue =
  issuerValue `elem` ["accounts.google.com", "https://accounts.google.com"]

specGoogleExpiryIsValid :: Integer -> Maybe Integer -> Bool
specGoogleExpiryIsValid now maybeExp =
  case maybeExp of
    Nothing -> True
    Just expirySeconds -> expirySeconds >= now

sampleGoogleTokenInfo :: GoogleTokenInfo
sampleGoogleTokenInfo =
  GoogleTokenInfo
    { tokenAud = "client-id"
    , tokenIss = "accounts.google.com"
    , tokenSub = "google-user-1"
    , tokenEmail = "learner@example.com"
    , tokenEmailVerified = Just (GoogleEmailVerifiedBool True)
    , tokenName = Just "Learner"
    , tokenPicture = Just "https://example.com/avatar.png"
    , tokenExp = Just "9999999999"
    }

sampleChoiceExercise :: ExercisePrompt
sampleChoiceExercise =
  ExercisePrompt
    { exerciseId = "sample-choice"
    , lessonId = "sample-lesson"
    , kind = MultipleChoice
    , prompt = "Choose the best reply."
    , promptDetail = Just "A: Hi, I am Yuki. ____"
    , choices = ["Nice to meet you.", "At seven."]
    , fragments = []
    , answerText = Nothing
    , acceptableAnswers = ["Nice to meet you."]
    , translation = Nothing
    , hint = Nothing
    , explanation = "Natural introduction reply."
    }

sampleOrderingExercise :: [String] -> ExercisePrompt
sampleOrderingExercise fragments =
  ExercisePrompt
    { exerciseId = "sample-ordering"
    , lessonId = "sample-lesson"
    , kind = Ordering
    , prompt = "Build the sentence."
    , promptDetail = Nothing
    , choices = []
    , fragments = fragments
    , answerText = Nothing
    , acceptableAnswers = [unwords fragments]
    , translation = Nothing
    , hint = Nothing
    , explanation = "Put the fragments in order."
    }

minimalUnitSummary :: Int -> Int -> UnitSummary
minimalUnitSummary completed total =
  UnitSummary
    { unitId = "unit-progress"
    , index = 1
    , title = "Progress"
    , cefrBand = "A1"
    , focus = "Progress"
    , lessonSummaries = []
    , completedLessons = completed
    , totalLessons = total
    , unlocked = True
    }

genUnitSummary :: Gen UnitSummary
genUnitSummary = do
  unitSuffix <- Gen.int (Range.linear 1 20)
  lessonSummaries <- Gen.list (Range.linear 0 4) (genLessonSummary unitSuffix)
  let completedLessons = length [() | LessonSummary {status = Completed} <- lessonSummaries]
      unlocked = any (\LessonSummary {status} -> status /= Locked) lessonSummaries
  pure
    UnitSummary
      { unitId = "unit-" <> show unitSuffix
      , index = unitSuffix
      , title = "Unit " <> show unitSuffix
      , cefrBand = "A1"
      , focus = "Focus " <> show unitSuffix
      , lessonSummaries = lessonSummaries
      , completedLessons = completedLessons
      , totalLessons = length lessonSummaries
      , unlocked = unlocked
      }

genLessonSummary :: Int -> Gen LessonSummary
genLessonSummary unitSuffix = do
  lessonSuffix <- Gen.int (Range.linear 1 8)
  status <- Gen.enumBounded
  masteryPercent <- Gen.int (Range.linear 0 100)
  pure
    LessonSummary
      { lessonId = "unit-" <> show unitSuffix <> "-lesson-" <> show lessonSuffix
      , unitId = "unit-" <> show unitSuffix
      , index = lessonSuffix
      , title = "Lesson " <> show lessonSuffix
      , subtitle = "Subtitle"
      , goal = "Goal"
      , xpReward = 40
      , exerciseCount = 4
      , status = status
      , masteryPercent = masteryPercent
      }

genLessonId :: Gen String
genLessonId = do
  unitSuffix <- Gen.int (Range.linear 1 20)
  lessonSuffix <- Gen.int (Range.linear 1 8)
  pure ("unit-" <> show unitSuffix <> "-lesson-" <> show lessonSuffix)

genAnswerText :: Gen String
genAnswerText =
  Gen.string
    (Range.linear 0 40)
    (Gen.element (['a' .. 'z'] <> ['A' .. 'Z'] <> ['0' .. '9'] <> "   "))

genFragment :: Gen String
genFragment =
  Gen.string
    (Range.linear 1 12)
    (Gen.element (['a' .. 'z'] <> ['A' .. 'Z'] <> ['0' .. '9'] <> "'-."))

genShuffleSeed :: Gen Rules.ShuffleSeed
genShuffleSeed =
  Rules.ShuffleSeed
    <$> Gen.string
      (Range.linear 0 32)
      (Gen.element (['a' .. 'z'] <> ['A' .. 'Z'] <> ['0' .. '9'] <> "-_:"))

genPlacementLevel :: Gen Placement.CefrLevel
genPlacementLevel =
  Gen.enumBounded

genDay :: Gen Day
genDay =
  ModifiedJulianDay <$> Gen.integral (Range.linear 50_000 80_000)

genLastActiveDay :: Day -> Gen (Maybe String)
genLastActiveDay today =
  Gen.choice
    [ pure Nothing
    , pure (Just (Rules.formatDay today))
    , pure (Just (Rules.formatDay (addDays (-1) today)))
    , pure (Just (Rules.formatDay (addDays (-2) today)))
    , pure (Just (Rules.formatDay (addDays 1 today)))
    , Just <$> Gen.element ["", "not-a-day", "2026-99-99"]
    ]

genMaybeGoogleEmailVerifiedWire :: Gen (Maybe GoogleEmailVerifiedWire)
genMaybeGoogleEmailVerifiedWire =
  Gen.choice
    [ pure Nothing
    , Just . GoogleEmailVerifiedBool <$> Gen.bool
    , Just . GoogleEmailVerifiedString . Text.pack
        <$> Gen.element ["true", "false", "TRUE", "FALSE", " True ", " False ", "yes", "no", "1", ""]
    ]

genClientId :: Gen String
genClientId =
  Gen.string (Range.linear 1 24) (Gen.element (['a' .. 'z'] <> ['0' .. '9'] <> "-_"))

genGoogleTokenClaims :: String -> Gen GoogleTokenClaims
genGoogleTokenClaims clientId = do
  aud <-
    Gen.element
      [ clientId
      , clientId <> "-other"
      , "different-client"
      ]
  iss <-
    Gen.element
      [ "accounts.google.com"
      , "https://accounts.google.com"
      , "https://evil.example"
      , ""
      ]
  emailVerified <- Gen.bool
  expValue <-
    Gen.choice
      [ pure Nothing
      , Just <$> Gen.integral (Range.linear 0 2_000_000_000)
      ]
  pure
    GoogleTokenClaims
      { claimAud = aud
      , claimIss = iss
      , claimSub = "google-user-" <> aud
      , claimEmail = "learner@example.com"
      , claimEmailVerified = emailVerified
      , claimName = Just "Learner"
      , claimPicture = Nothing
      , claimExp = expValue
      }
