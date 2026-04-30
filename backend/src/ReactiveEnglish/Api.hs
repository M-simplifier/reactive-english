{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module ReactiveEnglish.Api
  ( Api,
    apiProxy,
  )
where

import ReactiveEnglish.Schema.Generated
import Servant
import Web.Cookie (SetCookie)

type Api =
  "api"
    :> ( "session" :> Header "Cookie" String :> Get '[JSON] SessionSnapshot
           :<|> "auth" :> "google" :> ReqBody '[JSON] GoogleAuthRequest :> Post '[JSON] (Headers '[Header "Set-Cookie" SetCookie] SessionSnapshot)
           :<|> "auth" :> "dev" :> ReqBody '[JSON] DevLoginRequest :> Post '[JSON] (Headers '[Header "Set-Cookie" SetCookie] SessionSnapshot)
           :<|> "logout" :> Header "Cookie" String :> Post '[JSON] (Headers '[Header "Set-Cookie" SetCookie] SessionSnapshot)
           :<|> Header "Cookie" String
             :> ( "bootstrap" :> Get '[JSON] AppBootstrap
                    :<|> "placement" :> Get '[JSON] [PlacementQuestion]
                    :<|> "placement" :> ReqBody '[JSON] PlacementSubmission :> Post '[JSON] PlacementResult
                    :<|> "units" :> Capture "unitId" String :> Get '[JSON] UnitSummary
                    :<|> "lessons" :> Capture "lessonId" String :> Get '[JSON] LessonDetail
                    :<|> "attempts" :> ReqBody '[JSON] AttemptStart :> Post '[JSON] AttemptView
                    :<|> "attempts" :> Capture "attemptId" String :> "answer" :> ReqBody '[JSON] AnswerSubmission :> Post '[JSON] AttemptProgress
                    :<|> "attempts" :> Capture "attemptId" String :> "complete" :> Post '[JSON] AttemptCompletion
                    :<|> "review" :> Get '[JSON] [ReviewSummary]
                    :<|> "vocabulary" :> Get '[JSON] VocabularyDashboard
                    :<|> "vocabulary" :> "review" :> Get '[JSON] [VocabularyReviewPrompt]
                    :<|> "vocabulary" :> "review" :> ReqBody '[JSON] VocabularyReviewSubmission :> Post '[JSON] VocabularyReviewResult
                )
       )

apiProxy :: Proxy Api
apiProxy = Proxy
