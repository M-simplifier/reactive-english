module App.View
  ( render
  ) where

import Prelude (div, map, not, show, (&&), (*), (+), (-), (<<<), (<>), (==), (>=), (>>=))

import App.Model
  ( ActiveSession
  , ActivePlacementSession
  , AppState
  , AuthState(..)
  , DataSource(..)
  , DraftAnswer(..)
  , LoadState(..)
  , PlacementDraft(..)
  , PlacementState(..)
  , PreviewState(..)
  , SessionState(..)
  , VocabularyDraft(..)
  , VocabularyState(..)
  , activeExercise
  , activeProgressPercent
  , currentViewer
  , findLessonSummary
  , lessonIsStartable
  , placementActiveQuestion
  , selectedUnitSummary
  , vocabularyActivePrompt
  )
import App.Schema.Generated
  ( AnswerFeedback
  , AppBootstrap
  , DevLoginOption
  , ExerciseKind(..)
  , ExercisePrompt
  , KnowledgeDimension(..)
  , LessonStatus(..)
  , LessonSummary
  , PlacementQuestion
  , PlacementResult
  , ReviewSummary
  , SessionSnapshot
  , UnitSummary
  , VocabularyCard
  , VocabularyFeedback
  , VocabularyReviewPrompt
  )
import App.UiAction
  ( UiAction(..)
  , uiActionAttribute
  , uiSubmitAttribute
  )
import Data.Array as Array
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Data.String (Pattern(..), Replacement(..), joinWith, replaceAll)
import Data.String.CodeUnits as String

render :: AppState -> String
render state =
  joinWith ""
    [ "<div class=\"app-shell\">"
    , "<div class=\"sky-grid\"></div>"
    , "<div class=\"glow-orb glow-sun\"></div>"
    , "<div class=\"glow-orb glow-lagoon\"></div>"
    , "<div class=\"glow-orb glow-coral\"></div>"
    , renderTopbar state
    , "<main class=\"main-frame\">"
    , renderSurface state
    , "</main>"
    , renderVocabularyOverlay state
    , renderPlacementOverlay state
    , renderCompletionBanner state
    , "</div>"
    ]

renderTopbar :: AppState -> String
renderTopbar state =
  let
    sessionButton = case state.session of
      SessionActive _ -> "<button class=\"ghost-button nav-button\" " <> uiActionAttribute ActionBackDashboard <> " data-value=\"\">Dashboard</button>"
      SessionOpening _ -> "<button class=\"ghost-button nav-button\" " <> uiActionAttribute ActionBackDashboard <> " data-value=\"\">Cancel lesson</button>"
      SessionFailed _ -> "<button class=\"ghost-button nav-button\" " <> uiActionAttribute ActionBackDashboard <> " data-value=\"\">Back</button>"
      SessionClosed -> ""
    viewerMarkup = case currentViewer state of
      Just viewer ->
        joinWith ""
          [ "<div class=\"viewer-card\">"
          , "<span class=\"viewer-avatar\">"
          , initials viewer.displayName
          , "</span>"
          , "<span class=\"viewer-lines\">"
          , "<strong>"
          , escape viewer.displayName
          , "</strong>"
          , "<small>"
          , escape viewer.email
          , "</small>"
          , "</span>"
          , "</div>"
          , "<button class=\"ghost-button nav-button\" "
          , uiActionAttribute ActionLogout
          , " data-value=\"\">Switch</button>"
          ]
      Nothing ->
        ""
  in
    joinWith ""
      [ "<header class=\"topbar\">"
      , "<div class=\"brand-lockup\">"
      , "<div class=\"brand-mark\">RE</div>"
      , "<div>"
      , "<p class=\"eyebrow\">A1-C2 English mission deck</p>"
      , "<h1 class=\"brand\">Reactive English</h1>"
      , "</div>"
      , "</div>"
      , "<div class=\"topbar-actions\">"
      , renderSourcePill state.dataSource
      , viewerMarkup
      , sessionButton
      , "</div>"
      , "</header>"
      ]

renderSurface :: AppState -> String
renderSurface state =
  case state.auth of
    AuthLoading ->
      renderLoadingPanel "Checking your sign-in session..."

    AuthFailed message ->
      renderErrorPanel message

    AuthReady flow ->
      case flow.snapshot.viewer of
        Nothing ->
          renderSignedOut flow

        Just _ ->
          case state.session of
            SessionClosed ->
              renderDashboard state

            SessionOpening lessonId ->
              renderSessionLoading lessonId

            SessionFailed message ->
              renderSessionFailure message

            SessionActive session ->
              renderSession state session

renderSignedOut :: { snapshot :: SessionSnapshot, busy :: Boolean, message :: Maybe String } -> String
renderSignedOut flow =
  let
    googleBlock =
      if flow.snapshot.authConfig.googleEnabled then
        joinWith ""
          [ "<article class=\"auth-route-card google-route\">"
          , "<div class=\"auth-route-head\">"
          , "<span class=\"auth-symbol google-symbol\">G</span>"
          , "<div>"
          , "<p class=\"small-label\">Real account lane</p>"
          , "<h3>Sign in with Google</h3>"
          , "</div>"
          , "</div>"
          , "<p>Use this once to verify the production browser path. Progress, XP, streaks, and review cards attach to this user.</p>"
          , "<div class=\"google-button-frame\">"
          , "<div id=\"google-signin-button\" class=\"google-signin-slot\"></div>"
          , "</div>"
          , "<p class=\"microcopy\">The Google button is rendered by Google Identity Services after the page loads.</p>"
          , "</article>"
          ]
      else
        joinWith ""
          [ "<article class=\"auth-route-card google-route unavailable\">"
          , "<div class=\"auth-route-head\">"
          , "<span class=\"auth-symbol google-symbol\">G</span>"
          , "<div>"
          , "<p class=\"small-label\">Real account lane</p>"
          , "<h3>Google Sign-In is not configured</h3>"
          , "</div>"
          , "</div>"
          , "<p>Run <code>npm start</code> and enter <code>GOOGLE_CLIENT_ID</code> when prompted to enable this lane.</p>"
          , "</article>"
          ]
    devBlock =
      if flow.snapshot.authConfig.devLoginEnabled && not (Array.null flow.snapshot.authConfig.devLoginOptions) then
        joinWith ""
          [ "<article class=\"auth-route-card lab-route\">"
          , "<div class=\"auth-route-head\">"
          , "<span class=\"auth-symbol lab-symbol\">LAB</span>"
          , "<div>"
          , "<p class=\"small-label\">Local test lane</p>"
          , "<h3>Try user switching fast</h3>"
          , "</div>"
          , "</div>"
          , "<p>These local accounts bypass Google, but still use backend sessions and user-scoped progress.</p>"
          , "<div class=\"dev-login-grid\">"
          , joinWith "" (map renderDevLoginButton flow.snapshot.authConfig.devLoginOptions)
          , "</div>"
          , "</article>"
          ]
      else
        ""
    messageMarkup = renderOptionalParagraph "auth-message" flow.message
  in
    joinWith ""
      [ "<section class=\"landing-grid\">"
      , "<article class=\"landing-hero glass-card\">"
      , "<div class=\"hero-badge-row\">"
      , "<span class=\"route-badge\">96 lessons</span>"
      , "<span class=\"route-badge\">384 exercises</span>"
      , "<span class=\"route-badge\">A1 to C2</span>"
      , "</div>"
      , "<p class=\"eyebrow\">English that feels like a route, not a form</p>"
      , "<h2>Pick a sign-in lane and start today's mission.</h2>"
      , "<p class=\"hero-summary\">Reactive English is a typed FRP learning app built around one tight loop: choose a route, answer small challenges, get feedback, and keep your progress under the right user.</p>"
      , "<div class=\"landing-proof-grid\">"
      , renderProofTile "Typed progress" "Every lesson result is saved through the Haskell backend."
      , renderProofTile "FRP rhythm" "PureScript events keep the UI responsive without hiding state."
      , renderProofTile "Low-friction testing" "Google and dev-login lanes can coexist locally."
      , "</div>"
      , messageMarkup
      , if flow.busy then "<p class=\"auth-message\">Auth request in flight...</p>" else ""
      , "</article>"
      , "<aside class=\"signin-dock\">"
      , googleBlock
      , devBlock
      , "</aside>"
      , "</section>"
      ]

renderDevLoginButton :: DevLoginOption -> String
renderDevLoginButton option =
  joinWith ""
    [ "<button class=\"dev-login-button\" "
    , uiActionAttribute ActionDevLogin
    , " data-value=\""
    , escapeAttr option.email
    , "\">"
    , "<span class=\"dev-avatar\">"
    , initials option.displayName
    , "</span>"
    , "<span class=\"dev-copy\">"
    , "<strong>"
    , escape option.displayName
    , "</strong>"
    , "<small>"
    , escape option.email
    , "</small>"
    , "</span>"
    , "</button>"
    ]

renderDashboard :: AppState -> String
renderDashboard state =
  case state.bootstrap of
    NotAsked ->
      renderLoadingPanel "Preparing your study route..."

    Loading ->
      renderLoadingPanel "Loading dashboard and curriculum..."

    Failed message ->
      renderErrorPanel message

    Loaded bootstrap ->
      let
        recommendedCard = case bootstrap.recommendedLessonId >>= findLessonSummary bootstrap of
          Just lesson ->
            renderRecommendedCard lesson
          Nothing ->
            joinWith ""
              [ "<article class=\"next-mission-card\">"
              , "<p class=\"small-label\">Next mission</p>"
              , "<h3>Explore the open route</h3>"
              , "<p>Pick any unlocked lesson and keep your streak alive.</p>"
              , "</article>"
              ]
        unitMarkup = maybe (renderEmptyPreview "Choose a unit to open its mission route.") renderUnitBoard (selectedUnitSummary state)
        reviewMarkup =
          if Array.null bootstrap.reviewQueue then
            "<div class=\"empty-stack\"><strong>Clear sky.</strong><span>No review cards are due right now.</span></div>"
          else
            joinWith "" (map renderReviewCard bootstrap.reviewQueue)
      in
        joinWith ""
          [ renderModeNotice state.dataSource
          , "<section class=\"mission-hero glass-card\">"
          , "<div class=\"mission-copy\">"
          , "<p class=\"eyebrow\">Today's flight plan</p>"
          , "<h2>"
          , escape bootstrap.profile.learnerName
          , ", your next English island is ready.</h2>"
          , "<p class=\"hero-summary\">Short challenges, visible progress, and review pressure without clutter. Start one lesson, finish one loop, bank the XP.</p>"
          , "<div class=\"stat-constellation\">"
          , renderStatChip "XP" (show bootstrap.profile.xp)
          , renderStatChip "Streak" (show bootstrap.profile.streakDays <> " days")
          , renderStatChip "Lessons" (show bootstrap.profile.completedLessons <> "/" <> show bootstrap.profile.totalLessons)
          , renderStatChip "Accuracy" (show bootstrap.stats.accuracyPercent <> "%")
          , "</div>"
          , recommendedCard
          , "</div>"
          , "<aside class=\"mission-compass\">"
          , "<p class=\"small-label\">Current unit</p>"
          , "<h3>"
          , escape bootstrap.stats.currentUnitTitle
          , "</h3>"
          , "<p class=\"hero-progress-copy\">"
          , show bootstrap.stats.currentUnitProgressPercent
          , "% of this unit is charted.</p>"
          , renderMeter bootstrap.stats.currentUnitProgressPercent
          , "<div class=\"compass-mini-row\">"
          , "<span><strong>"
          , show bootstrap.stats.dueReviews
          , "</strong> due reviews</span>"
          , "<span><strong>"
          , show (Array.length bootstrap.units)
          , "</strong> units</span>"
          , "</div>"
          , "</aside>"
          , "</section>"
          , "<section class=\"workspace-grid\">"
          , "<div class=\"route-column\">"
          , renderUnitTabs state bootstrap.units
          , unitMarkup
          , "</div>"
          , "<aside class=\"side-rail\">"
          , renderPlacementHub bootstrap
          , renderVocabularyHub bootstrap
          , "<section class=\"glass-card queue-card\">"
          , "<p class=\"small-label\">Review weather</p>"
          , "<h3>Cards for the next pass</h3>"
          , reviewMarkup
          , "</section>"
          , renderPreview state.preview
          , "</aside>"
          , "</section>"
          ]

renderRecommendedCard :: LessonSummary -> String
renderRecommendedCard lesson =
  joinWith ""
    [ "<article class=\"next-mission-card\">"
    , "<div>"
    , "<p class=\"small-label\">Next mission</p>"
    , "<h3>"
    , escape lesson.title
    , "</h3>"
    , "<p>"
    , escape lesson.goal
    , "</p>"
    , "</div>"
    , "<button class=\"primary-button\" "
    , uiActionAttribute ActionStartLesson
    , " data-value=\""
    , escapeAttr lesson.lessonId
    , "\">Start mission</button>"
    , "</article>"
    ]

renderUnitBoard :: UnitSummary -> String
renderUnitBoard unit =
  joinWith ""
    [ "<section class=\"glass-card island-board\">"
    , "<div class=\"island-header\">"
    , "<div>"
    , "<p class=\"small-label\">Unit "
    , show unit.index
    , " / "
    , escape unit.cefrBand
    , "</p>"
    , "<h3>"
    , escape unit.title
    , "</h3>"
    , "<p>"
    , escape unit.focus
    , "</p>"
    , "</div>"
    , "<div class=\"unit-meter-block\">"
    , "<span class=\"meter-caption\">"
    , show unit.completedLessons
    , " of "
    , show unit.totalLessons
    , " lessons complete</span>"
    , renderMeter (if unit.totalLessons == 0 then 0 else div (unit.completedLessons * 100) unit.totalLessons)
    , "</div>"
    , "</div>"
    , "<div class=\"quest-path\">"
    , joinWith "" (map renderLessonCard unit.lessonSummaries)
    , "</div>"
    , "</section>"
    ]

renderLessonCard :: LessonSummary -> String
renderLessonCard lesson =
  let
    actionButton =
      if lessonIsStartable lesson then
        joinWith ""
          [ "<button class=\"secondary-button\" "
          , uiActionAttribute ActionPreviewLesson
          , " data-value=\""
          , escapeAttr lesson.lessonId
          , "\">Preview</button>"
          ]
      else
        "<button class=\"secondary-button\" disabled>Locked</button>"
    statusClass = "status-" <> statusClassName lesson.status
  in
    joinWith ""
      [ "<article class=\"quest-card "
      , statusClass
      , "\">"
      , "<div class=\"quest-node\">"
      , show lesson.index
      , "</div>"
      , "<div class=\"quest-content\">"
      , "<div class=\"quest-card-head\">"
      , "<div>"
      , "<p class=\"small-label\">"
      , escape lesson.subtitle
      , "</p>"
      , "<h4>"
      , escape lesson.title
      , "</h4>"
      , "</div>"
      , "<span class=\"status-pill\">"
      , escape (statusLabel lesson.status)
      , "</span>"
      , "</div>"
      , "<p class=\"lesson-goal\">"
      , escape lesson.goal
      , "</p>"
      , "<div class=\"lesson-meta\">"
      , "<span>"
      , show lesson.exerciseCount
      , " drills</span>"
      , "<span>"
      , show lesson.xpReward
      , " XP</span>"
      , "<span>"
      , show lesson.masteryPercent
      , "% mastery</span>"
      , "</div>"
      , actionButton
      , "</div>"
      , "</article>"
      ]

renderUnitTabs :: AppState -> Array UnitSummary -> String
renderUnitTabs state units =
  joinWith ""
    [ "<section class=\"unit-switcher\" aria-label=\"Course units\">"
    , joinWith "" (map (renderUnitTab state.selectedUnitId) units)
    , "</section>"
    ]

renderUnitTab :: Maybe String -> UnitSummary -> String
renderUnitTab selectedUnitId unit =
  let
    selectedClass =
      if Just unit.unitId == selectedUnitId then " selected" else ""
    lockedClass =
      if unit.unlocked then "" else " locked"
  in
    joinWith ""
      [ "<button class=\"unit-tab"
      , selectedClass
      , lockedClass
      , "\" "
      , uiActionAttribute ActionSelectUnit
      , " data-value=\""
      , escapeAttr unit.unitId
      , "\">"
      , "<span class=\"unit-number\">"
      , show unit.index
      , "</span>"
      , "<span class=\"unit-tab-copy\">"
      , "<strong>"
      , escape unit.title
      , "</strong>"
      , "<small>"
      , escape unit.cefrBand
      , " / "
      , if unit.unlocked then "open" else "locked"
      , "</small>"
      , "</span>"
      , "</button>"
      ]

renderReviewCard :: ReviewSummary -> String
renderReviewCard review =
  joinWith ""
    [ "<article class=\"review-card\">"
    , "<div>"
    , "<p class=\"small-label\">"
    , escape review.dueLabel
    , "</p>"
    , "<h4>"
    , escape review.lessonTitle
    , "</h4>"
    , "<p>"
    , escape review.prompt
    , "</p>"
    , "</div>"
    , "<div class=\"review-footer\">"
    , "<span>"
    , show review.masteryPercent
    , "% mastery</span>"
    , "<button class=\"ghost-button compact-button\" "
    , uiActionAttribute ActionStartLesson
    , " data-value=\""
    , escapeAttr review.lessonId
    , "\">Review</button>"
    , "</div>"
    , "</article>"
    ]

renderVocabularyHub :: AppBootstrap -> String
renderVocabularyHub bootstrap =
  let
    vocabulary = bootstrap.vocabulary
    focusMarkup =
      if Array.null vocabulary.focusWords then
        "<div class=\"empty-stack\"><strong>No word deck yet.</strong><span>Seeded vocabulary will appear after the curriculum loads.</span></div>"
      else
        joinWith "" (map renderVocabularyCard vocabulary.focusWords)
    reviewButton =
      if Array.null vocabulary.reviewQueue then
        "<button class=\"secondary-button\" " <> uiActionAttribute ActionStartVocabularyReview <> " data-value=\"\">Check for words</button>"
      else
        "<button class=\"primary-button\" " <> uiActionAttribute ActionStartVocabularyReview <> " data-value=\"\">Start word mission</button>"
  in
    joinWith ""
      [ "<section class=\"glass-card vocab-card\">"
      , "<div class=\"vocab-card-head\">"
      , "<div>"
      , "<p class=\"small-label\">Word mission</p>"
      , "<h3>Vocabulary cockpit</h3>"
      , "</div>"
      , "<span class=\"kind-badge\">"
      , show vocabulary.dueCount
      , " due</span>"
      , "</div>"
      , "<p class=\"hero-progress-copy\">"
      , show vocabulary.totalTracked
      , " tracked words, "
      , show vocabulary.averageMasteryPercent
      , "% average mastery.</p>"
      , renderMeter vocabulary.averageMasteryPercent
      , "<div class=\"vocab-focus-list\">"
      , focusMarkup
      , "</div>"
      , reviewButton
      , "</section>"
      ]

renderPlacementHub :: AppBootstrap -> String
renderPlacementHub bootstrap =
  joinWith ""
    [ "<section class=\"glass-card placement-card\">"
    , "<div class=\"vocab-card-head\">"
    , "<div>"
    , "<p class=\"small-label\">Level jump</p>"
    , "<h3>Placement radar</h3>"
    , "</div>"
    , "<span class=\"kind-badge\">A1-C2</span>"
    , "</div>"
    , "<p class=\"hero-progress-copy\">Skip material you already command. A strong result opens the first lesson at your placed band and banks the matching XP bonus once.</p>"
    , "<div class=\"placement-stat-row\">"
    , "<span><strong>"
    , show bootstrap.profile.completedLessons
    , "</strong> completed</span>"
    , "<span><strong>"
    , show bootstrap.profile.totalLessons
    , "</strong> total</span>"
    , "</div>"
    , "<button class=\"primary-button\" "
    , uiActionAttribute ActionStartPlacement
    , " data-value=\"\">Take placement test</button>"
    , "</section>"
    ]

renderPlacementOverlay :: AppState -> String
renderPlacementOverlay state =
  case state.placementSession of
    PlacementClosed ->
      ""

    PlacementLoading ->
      joinWith ""
        [ "<div class=\"vocabulary-overlay placement-overlay\">"
        , "<section class=\"glass-card vocabulary-panel placement-panel\">"
        , "<p class=\"small-label\">Placement radar</p>"
        , "<h3>Loading the A1-C2 route check...</h3>"
        , "</section>"
        , "</div>"
        ]

    PlacementError message ->
      joinWith ""
        [ "<div class=\"vocabulary-overlay placement-overlay\">"
        , "<section class=\"glass-card vocabulary-panel placement-panel\">"
        , "<p class=\"small-label\">Placement radar</p>"
        , "<h3>Placement test unavailable</h3>"
        , "<p>"
        , escape message
        , "</p>"
        , "<button class=\"primary-button\" "
        , uiActionAttribute ActionClosePlacement
        , " data-value=\"\">Back to dashboard</button>"
        , "</section>"
        , "</div>"
        ]

    PlacementActive session ->
      case session.result of
        Just result ->
          renderPlacementResult result

        Nothing ->
          case placementActiveQuestion session of
            Nothing ->
              ""

            Just question ->
              joinWith ""
                [ "<div class=\"vocabulary-overlay placement-overlay\">"
                , "<section class=\"glass-card vocabulary-panel placement-panel\">"
                , "<div class=\"exercise-head\">"
                , "<div>"
                , "<p class=\"small-label\">Question "
                , show (session.currentIndex + 1)
                , " / "
                , show (Array.length session.questions)
                , " - "
                , escape question.cefrBand
                , " / "
                , escape question.skill
                , "</p>"
                , "<h3>"
                , escape question.prompt
                , "</h3>"
                , renderOptionalParagraph "prompt-detail" question.promptDetail
                , "</div>"
                , "<button class=\"ghost-button compact-button\" "
                , uiActionAttribute ActionClosePlacement
                , " data-value=\"\">Close</button>"
                , "</div>"
                , renderPlacementBody question session
                , renderSessionMessage session.message
                , "</section>"
                , "</div>"
                ]

renderPlacementBody :: PlacementQuestion -> ActivePlacementSession -> String
renderPlacementBody question session =
  joinWith ""
    [ "<div class=\"choice-grid\">"
    , joinWith "" (mapWithIndex (renderPlacementChoice session.draft) question.choices)
    , "</div>"
    , "<button class=\"primary-button\" "
    , uiActionAttribute ActionContinuePlacement
    , " data-value=\"\""
    , if session.submitting then " disabled" else ""
    , ">"
    , if session.currentIndex + 1 >= Array.length session.questions then "Score placement" else "Next question"
    , "</button>"
    ]

renderPlacementChoice :: PlacementDraft -> Int -> String -> String
renderPlacementChoice draft index choice =
  let
    selectedClass = case draft of
      PlacementChoiceDraft selectedIndex | selectedIndex == index -> " selected"
      _ -> ""
  in
    joinWith ""
      [ "<button class=\"choice-button"
      , selectedClass
      , "\" "
      , uiActionAttribute ActionChoosePlacementChoice
      , " data-value=\""
      , show index
      , "\">"
      , escape choice
      , "</button>"
      ]

renderPlacementResult :: PlacementResult -> String
renderPlacementResult result =
  joinWith ""
    [ "<div class=\"vocabulary-overlay placement-overlay\">"
    , "<section class=\"glass-card vocabulary-panel placement-panel placement-result\">"
    , "<p class=\"small-label\">Placement complete</p>"
    , "<h3>You placed at "
    , escape result.placedCefrBand
    , "</h3>"
    , "<p>Your score was "
    , show result.scorePercent
    , "%. The route has been refreshed around your level.</p>"
    , "<div class=\"feedback-meta\">"
    , "<span>"
    , show result.xpAwarded
    , " XP awarded</span>"
    , "<span>"
    , show result.completedLessonsDelta
    , " lessons skipped</span>"
    , maybe "" (\lessonId -> "<span>Next: " <> escape lessonId <> "</span>") result.recommendedLessonId
    , "</div>"
    , "<button class=\"primary-button\" "
    , uiActionAttribute ActionClosePlacement
    , " data-value=\"\">Open refreshed dashboard</button>"
    , "</section>"
    , "</div>"
    ]

renderVocabularyCard :: VocabularyCard -> String
renderVocabularyCard card =
  joinWith ""
    [ "<article class=\"word-card-mini\">"
    , "<div>"
    , "<strong>"
    , escape card.headword
    , "</strong>"
    , "<span>"
    , escape card.partOfSpeech
    , " / "
    , escape card.cefrBand
    , "</span>"
    , "</div>"
    , "<p>"
    , escape card.definition
    , "</p>"
    , "<div class=\"review-footer\">"
    , "<span>"
    , escape card.dueLabel
    , "</span>"
    , "<span>"
    , show card.masteryPercent
    , "%</span>"
    , "</div>"
    , "</article>"
    ]

renderVocabularyOverlay :: AppState -> String
renderVocabularyOverlay state =
  case state.vocabularySession of
    VocabularyClosed ->
      ""

    VocabularyLoading ->
      joinWith ""
        [ "<div class=\"vocabulary-overlay\">"
        , "<section class=\"glass-card vocabulary-panel\">"
        , "<p class=\"small-label\">Word mission</p>"
        , "<h3>Checking your due cards...</h3>"
        , "</section>"
        , "</div>"
        ]

    VocabularyFailed message ->
      joinWith ""
        [ "<div class=\"vocabulary-overlay\">"
        , "<section class=\"glass-card vocabulary-panel\">"
        , "<p class=\"small-label\">Word mission</p>"
        , "<h3>No review opened</h3>"
        , "<p>"
        , escape message
        , "</p>"
        , "<button class=\"primary-button\" "
        , uiActionAttribute ActionCloseVocabularyReview
        , " data-value=\"\">Back to dashboard</button>"
        , "</section>"
        , "</div>"
        ]

    VocabularyActive session ->
      case vocabularyActivePrompt session of
        Nothing ->
          ""

        Just prompt ->
          joinWith ""
            [ "<div class=\"vocabulary-overlay\">"
            , "<section class=\"glass-card vocabulary-panel\">"
            , "<div class=\"exercise-head\">"
            , "<div>"
            , "<p class=\"small-label\">Word "
            , show (session.currentIndex + 1)
            , " / "
            , show (Array.length session.prompts)
            , " - "
            , escape (dimensionLabel prompt.dimension)
            , "</p>"
            , "<h3>"
            , escape prompt.prompt
            , "</h3>"
            , renderOptionalParagraph "prompt-detail" prompt.promptDetail
            , "</div>"
            , "<button class=\"ghost-button compact-button\" "
            , uiActionAttribute ActionCloseVocabularyReview
            , " data-value=\"\">Close</button>"
            , "</div>"
            , renderVocabularyBody prompt session.draft session.feedback
            , renderOptionalParagraph "hint-callout" prompt.hint
            , renderSessionMessage session.message
            , renderVocabularyFeedback prompt session.feedback (session.currentIndex + 1 >= Array.length session.prompts)
            , "</section>"
            , "</div>"
            ]

renderVocabularyBody :: VocabularyReviewPrompt -> VocabularyDraft -> Maybe VocabularyFeedback -> String
renderVocabularyBody prompt draft feedback =
  case feedback of
    Just _ ->
      renderVocabularyLockedAnswer prompt draft

    Nothing ->
      if Array.null prompt.choices then
        let
          currentText = case draft of
            VocabularyTextDraft answer -> answer
            _ -> ""
        in
          joinWith ""
            [ "<form class=\"answer-form\" "
            , uiSubmitAttribute ActionSubmitVocabularyText
            , ">"
            , "<label class=\"input-label\" for=\"vocabularyAnswerText\">Type your answer</label>"
            , "<input id=\"vocabularyAnswerText\" name=\"answerText\" class=\"text-input\" value=\""
            , escapeAttr currentText
            , "\" autocomplete=\"off\" spellcheck=\"false\" />"
            , "<button class=\"primary-button\" type=\"submit\">Check word</button>"
            , "</form>"
            ]
      else
        joinWith ""
          [ "<div class=\"choice-grid\">"
          , joinWith "" (mapWithIndex (renderVocabularyChoice draft) prompt.choices)
          , "</div>"
          , "<button class=\"primary-button\" "
          , uiActionAttribute ActionCheckVocabularyAnswer
          , " data-value=\"\">Check word</button>"
          ]

renderVocabularyLockedAnswer :: VocabularyReviewPrompt -> VocabularyDraft -> String
renderVocabularyLockedAnswer prompt draft =
  case draft of
    VocabularyChoiceDraft choiceIndex ->
      "<div class=\"locked-answer\">" <> escape (fromMaybe "" (Array.index prompt.choices choiceIndex)) <> "</div>"
    VocabularyTextDraft answer ->
      "<div class=\"locked-answer\">" <> escape answer <> "</div>"
    VocabularyNoDraft ->
      ""

renderVocabularyChoice :: VocabularyDraft -> Int -> String -> String
renderVocabularyChoice draft index choice =
  let
    selectedClass = case draft of
      VocabularyChoiceDraft selectedIndex | selectedIndex == index -> " selected"
      _ -> ""
  in
    joinWith ""
      [ "<button class=\"choice-button"
      , selectedClass
      , "\" "
      , uiActionAttribute ActionChooseVocabularyChoice
      , " data-value=\""
      , show index
      , "\">"
      , escape choice
      , "</button>"
      ]

renderVocabularyFeedback :: VocabularyReviewPrompt -> Maybe VocabularyFeedback -> Boolean -> String
renderVocabularyFeedback _ Nothing _ = ""

renderVocabularyFeedback prompt (Just feedback) finished =
  joinWith ""
    [ "<section class=\"feedback-panel "
    , if feedback.correct then "correct" else "incorrect"
    , "\">"
    , "<p class=\"small-label\">"
    , if feedback.correct then "Word strengthened" else "Review again soon"
    , "</p>"
    , "<h4>"
    , escape feedback.explanation
    , "</h4>"
    , "<p>Expected answer: <strong>"
    , escape feedback.expectedAnswer
    , "</strong></p>"
    , "<div class=\"feedback-meta\">"
    , "<span>"
    , escape (dimensionLabel prompt.dimension)
    , "</span>"
    , "<span>"
    , show feedback.xpDelta
    , " XP</span>"
    , "<span>"
    , show feedback.masteryPercent
    , "% mastery</span>"
    , "</div>"
    , "<button class=\"primary-button\" "
    , uiActionAttribute ActionAdvanceVocabulary
    , " data-value=\"\">"
    , if finished then "Finish word mission" else "Next word"
    , "</button>"
    , "</section>"
    ]

renderPreview :: PreviewState -> String
renderPreview preview =
  case preview of
    PreviewClosed ->
      renderEmptyPreview "Select an unlocked lesson to inspect the story, tips, and exercise mix before launch."

    PreviewLoading _ ->
      renderEmptyPreview "Fetching lesson detail..."

    PreviewFailed _ message ->
      renderEmptyPreview ("Lesson preview failed: " <> message)

    PreviewReady detail ->
      joinWith ""
        [ "<section class=\"glass-card preview-card\">"
        , "<div class=\"preview-head\">"
        , "<div>"
        , "<p class=\"small-label\">Mission preview</p>"
        , "<h3>"
        , escape detail.lesson.title
        , "</h3>"
        , "<p>"
        , escape detail.narrative
        , "</p>"
        , "</div>"
        , "<button class=\"ghost-button compact-button\" "
        , uiActionAttribute ActionClosePreview
        , " data-value=\"\">Close</button>"
        , "</div>"
        , "<div class=\"preview-meta\">"
        , "<span>"
        , show detail.lesson.exerciseCount
        , " drills</span>"
        , "<span>"
        , show detail.lesson.xpReward
        , " XP</span>"
        , "<span>"
        , escape detail.lesson.subtitle
        , "</span>"
        , "</div>"
        , "<div class=\"tip-list\">"
        , joinWith "" (map renderTip detail.tips)
        , "</div>"
        , "<div class=\"exercise-type-strip\">"
        , joinWith "" (map renderExerciseTag detail.exercises)
        , "</div>"
        , "<button class=\"primary-button\" "
        , uiActionAttribute ActionStartLesson
        , " data-value=\""
        , escapeAttr detail.lesson.lessonId
        , "\">Start this mission</button>"
        , "</section>"
        ]

renderSessionLoading :: String -> String
renderSessionLoading lessonId =
  joinWith ""
    [ "<section class=\"glass-card state-card\">"
    , "<p class=\"small-label\">Opening lesson</p>"
    , "<h2>Preparing "
    , escape lessonId
    , "</h2>"
    , "<p>The lesson runtime is syncing prompts, state, and answer flow.</p>"
    , "</section>"
    ]

renderSessionFailure :: String -> String
renderSessionFailure message =
  joinWith ""
    [ "<section class=\"glass-card state-card\">"
    , "<p class=\"small-label\">Lesson error</p>"
    , "<h2>Could not open the lesson</h2>"
    , "<p>"
    , escape message
    , "</p>"
    , "<button class=\"primary-button\" "
    , uiActionAttribute ActionBackDashboard
    , " data-value=\"\">Return to dashboard</button>"
    , "</section>"
    ]

renderSession :: AppState -> ActiveSession -> String
renderSession state session =
  case activeExercise session of
    Nothing ->
      renderSessionFailure "The lesson has no current exercise."

    Just exercise ->
      joinWith ""
        [ renderModeNotice state.dataSource
        , "<section class=\"challenge-layout\">"
        , "<aside class=\"glass-card challenge-map\">"
        , "<p class=\"small-label\">Mission in progress</p>"
        , "<h2>"
        , escape session.attempt.lesson.title
        , "</h2>"
        , "<p>"
        , escape session.attempt.narrative
        , "</p>"
        , renderMeter (activeProgressPercent session)
        , "<p class=\"hero-progress-copy\">"
        , show session.answeredCount
        , " of "
        , show (Array.length session.attempt.exercises)
        , " answered, "
        , show session.correctCount
        , " correct.</p>"
        , "<div class=\"tip-list\">"
        , joinWith "" (map renderTip session.attempt.tips)
        , "</div>"
        , "</aside>"
        , "<section class=\"glass-card challenge-stage\">"
        , "<div class=\"exercise-head\">"
        , "<div>"
        , "<p class=\"small-label\">Challenge "
        , show (session.currentIndex + 1)
        , " / "
        , show (Array.length session.attempt.exercises)
        , "</p>"
        , "<h3>"
        , escape exercise.prompt
        , "</h3>"
        , renderOptionalParagraph "prompt-detail" exercise.promptDetail
        , "</div>"
        , "<span class=\"kind-badge\">"
        , escape (kindLabel exercise.kind)
        , "</span>"
        , "</div>"
        , renderExerciseBody exercise session.draft session.feedback
        , renderOptionalParagraph "hint-callout" exercise.hint
        , renderSessionMessage session.message
        , renderFeedback exercise session.feedback session.finished
        , "</section>"
        , "</section>"
        ]

renderExerciseBody :: ExercisePrompt -> DraftAnswer -> Maybe AnswerFeedback -> String
renderExerciseBody exercise draft feedback =
  case feedback of
    Just _ ->
      renderLockedAnswer exercise draft

    Nothing ->
      case exercise.kind of
        MultipleChoice ->
          joinWith ""
            [ "<div class=\"choice-grid\">"
            , joinWith "" (mapWithIndex (renderChoice draft) exercise.choices)
            , "</div>"
            , "<button class=\"primary-button\" "
            , uiActionAttribute ActionCheckAnswer
            , " data-value=\"\">Check answer</button>"
            ]

        Cloze ->
          let
            currentText = case draft of
              TextDraft answer -> answer
              _ -> ""
          in
            joinWith ""
              [ "<form class=\"answer-form\" "
              , uiSubmitAttribute ActionSubmitText
              , ">"
              , "<label class=\"input-label\" for=\"answerText\">Type the missing word or phrase</label>"
              , "<input id=\"answerText\" name=\"answerText\" class=\"text-input\" value=\""
              , escapeAttr currentText
              , "\" autocomplete=\"off\" spellcheck=\"false\" />"
              , "<button class=\"primary-button\" type=\"submit\">Check answer</button>"
              , "</form>"
              ]

        Ordering ->
          renderOrdering exercise draft

        TrueFalse ->
          joinWith ""
            [ "<div class=\"choice-grid tf-grid\">"
            , renderBooleanButton draft true
            , renderBooleanButton draft false
            , "</div>"
            , "<button class=\"primary-button\" "
            , uiActionAttribute ActionCheckAnswer
            , " data-value=\"\">Check answer</button>"
            ]

renderLockedAnswer :: ExercisePrompt -> DraftAnswer -> String
renderLockedAnswer exercise draft =
  case exercise.kind of
    Cloze ->
      let
        currentText = case draft of
          TextDraft answer -> answer
          _ -> fromMaybe "" exercise.answerText
      in
        joinWith ""
          [ "<div class=\"answer-lockup\">"
          , "<span class=\"small-label\">Your answer</span>"
          , "<div class=\"locked-answer\">"
          , escape currentText
          , "</div>"
          , "</div>"
          ]

    Ordering ->
      let
        selected = case draft of
          OrderingDraft indexes -> Array.mapMaybe (\index -> Array.index exercise.fragments index) indexes
          _ -> []
      in
        joinWith ""
          [ "<div class=\"ordering-selected\">"
          , joinWith "" (map renderLockedChip selected)
          , "</div>"
          ]

    MultipleChoice ->
      case draft of
        ChoiceDraft choiceIndex ->
          let
            selected = fromMaybe "" (Array.index exercise.choices choiceIndex)
          in
            "<div class=\"locked-answer\">" <> escape selected <> "</div>"
        _ ->
          ""

    TrueFalse ->
      case draft of
        BooleanDraft boolValue ->
          "<div class=\"locked-answer\">" <> (if boolValue then "True" else "False") <> "</div>"
        _ ->
          ""

renderOrdering :: ExercisePrompt -> DraftAnswer -> String
renderOrdering exercise draft =
  let
    selectedIndexes = case draft of
      OrderingDraft indexes -> indexes
      _ -> []
    selectedFragments = Array.mapMaybe (\index -> Array.index exercise.fragments index) selectedIndexes
    bankIndexes = Array.filter (\index -> not (Array.elem index selectedIndexes)) (Array.range 0 (Array.length exercise.fragments - 1))
  in
    joinWith ""
      [ "<div class=\"ordering-selected\">"
      , if Array.null selectedIndexes then "<p class=\"tray-copy\">Tap the fragments in order.</p>" else joinWith "" (map (renderSelectedFragment exercise.fragments) selectedIndexes)
      , "</div>"
      , "<div class=\"fragment-bank\">"
      , joinWith "" (map (\index -> renderFragmentButton exercise.fragments index) bankIndexes)
      , "</div>"
      , "<p class=\"tray-copy\">Current sentence: "
      , escape (joinWith " " selectedFragments)
      , "</p>"
      , "<button class=\"primary-button\" "
      , uiActionAttribute ActionCheckAnswer
      , " data-value=\"\">Check answer</button>"
      ]

renderSelectedFragment :: Array String -> Int -> String
renderSelectedFragment fragments index =
  let
    fragment = fromMaybe "" (Array.index fragments index)
  in
    joinWith ""
      [ "<button class=\"fragment-chip selected\" "
      , uiActionAttribute ActionOrderingUnpick
      , " data-value=\""
      , show index
      , "\">"
      , escape fragment
      , "</button>"
      ]

renderFragmentButton :: Array String -> Int -> String
renderFragmentButton fragments index =
  let
    fragment = fromMaybe "" (Array.index fragments index)
  in
    joinWith ""
      [ "<button class=\"fragment-chip\" "
      , uiActionAttribute ActionOrderingPick
      , " data-value=\""
      , show index
      , "\">"
      , escape fragment
      , "</button>"
      ]

renderChoice :: DraftAnswer -> Int -> String -> String
renderChoice draft index choice =
  let
    selectedClass = case draft of
      ChoiceDraft selectedIndex | selectedIndex == index -> " selected"
      _ -> ""
  in
    joinWith ""
      [ "<button class=\"choice-button"
      , selectedClass
      , "\" "
      , uiActionAttribute ActionChooseChoice
      , " data-value=\""
      , show index
      , "\">"
      , escape choice
      , "</button>"
      ]

renderBooleanButton :: DraftAnswer -> Boolean -> String
renderBooleanButton draft value =
  let
    selectedClass = case draft of
      BooleanDraft current | current == value -> " selected"
      _ -> ""
  in
    joinWith ""
      [ "<button class=\"choice-button"
      , selectedClass
      , "\" "
      , uiActionAttribute ActionChooseBoolean
      , " data-value=\""
      , if value then "true" else "false"
      , "\">"
      , if value then "True" else "False"
      , "</button>"
      ]

renderFeedback :: ExercisePrompt -> Maybe AnswerFeedback -> Boolean -> String
renderFeedback _ Nothing _ = ""

renderFeedback exercise (Just feedback) finished =
  joinWith ""
    [ "<section class=\"feedback-panel "
    , if feedback.correct then "correct" else "incorrect"
    , "\">"
    , "<p class=\"small-label\">"
    , if feedback.correct then "Correct" else "Not quite"
    , "</p>"
    , "<h4>"
    , escape feedback.explanation
    , "</h4>"
    , "<p>Expected answer: <strong>"
    , escape feedback.expectedAnswer
    , "</strong></p>"
    , renderOptionalParagraph "translation-note" exercise.translation
    , "<div class=\"feedback-meta\">"
    , "<span>"
    , show feedback.xpDelta
    , " XP</span>"
    , "<span>"
    , show feedback.nextReviewHours
    , "h until review</span>"
    , "<span>"
    , show feedback.masteryPercent
    , "% mastery</span>"
    , "</div>"
    , "<button class=\"primary-button\" "
    , uiActionAttribute ActionAdvance
    , " data-value=\"\">"
    , if finished then "Finish lesson" else "Continue"
    , "</button>"
    , "</section>"
    ]

renderSessionMessage :: Maybe String -> String
renderSessionMessage message =
  maybe "" (\text -> "<p class=\"session-message\">" <> escape text <> "</p>") message

renderLoadingPanel :: String -> String
renderLoadingPanel message =
  joinWith ""
    [ "<section class=\"glass-card state-card loading-card\">"
    , "<p class=\"small-label\">Loading</p>"
    , "<h2>Preparing the deck</h2>"
    , "<p>"
    , escape message
    , "</p>"
    , "</section>"
    ]

renderErrorPanel :: String -> String
renderErrorPanel message =
  joinWith ""
    [ "<section class=\"glass-card state-card\">"
    , "<p class=\"small-label\">Connection</p>"
    , "<h2>Dashboard unavailable</h2>"
    , "<p>"
    , escape message
    , "</p>"
    , "<button class=\"primary-button\" "
    , uiActionAttribute ActionRetryBootstrap
    , " data-value=\"\">Retry</button>"
    , "</section>"
    ]

renderEmptyPreview :: String -> String
renderEmptyPreview message =
  "<section class=\"glass-card preview-card empty\"><p class=\"small-label\">Mission preview</p><p>" <> escape message <> "</p></section>"

renderModeNotice :: DataSource -> String
renderModeNotice source =
  case source of
    LiveBackend -> ""
    DemoFallback ->
      joinWith ""
        [ "<section class=\"mode-banner\">"
        , "<div class=\"mode-banner-copy\">"
        , "<strong>Demo mode.</strong> "
        , "The first request to <code>/api/bootstrap</code> did not reach the live API, "
        , "so the SPA is currently using the in-memory demo curriculum. "
        , "Click retry after the server is ready."
        , "</div>"
        , "<button class=\"secondary-button\" "
        , uiActionAttribute ActionRetryBootstrap
        , " data-value=\"\">Retry live backend</button>"
        , "</section>"
        ]

renderCompletionBanner :: AppState -> String
renderCompletionBanner state =
  case state.banner of
    Nothing -> ""
    Just banner ->
      joinWith ""
        [ "<div class=\"completion-overlay\">"
        , "<section class=\"glass-card completion-card\">"
        , "<p class=\"small-label\">Mission saved</p>"
        , "<h3>"
        , escape banner.title
        , "</h3>"
        , "<p>"
        , escape banner.detail
        , "</p>"
        , "<div class=\"feedback-meta\">"
        , "<span>"
        , show banner.xpAwarded
        , " XP added</span>"
        , maybe "" (\lessonId -> "<span>Unlocked: " <> escape lessonId <> "</span>") banner.unlockedLessonId
        , "</div>"
        , "<button class=\"primary-button\" "
        , uiActionAttribute ActionDismissBanner
        , " data-value=\"\">Keep studying</button>"
        , "</section>"
        , "</div>"
        ]

renderSourcePill :: DataSource -> String
renderSourcePill source =
  let
    label = case source of
      LiveBackend -> "Live API"
      DemoFallback -> "Demo data"
  in
    "<span class=\"source-pill\">" <> escape label <> "</span>"

renderStatChip :: String -> String -> String
renderStatChip label value =
  joinWith ""
    [ "<div class=\"stat-chip\">"
    , "<span>"
    , escape label
    , "</span>"
    , "<strong>"
    , escape value
    , "</strong>"
    , "</div>"
    ]

renderProofTile :: String -> String -> String
renderProofTile title body =
  joinWith ""
    [ "<div class=\"proof-tile\">"
    , "<strong>"
    , escape title
    , "</strong>"
    , "<span>"
    , escape body
    , "</span>"
    , "</div>"
    ]

renderTip :: String -> String
renderTip tip =
  "<div class=\"tip-item\">" <> escape tip <> "</div>"

renderExerciseTag :: ExercisePrompt -> String
renderExerciseTag exercise =
  "<span class=\"exercise-tag\">" <> escape (kindLabel exercise.kind) <> "</span>"

renderMeter :: Int -> String
renderMeter percent =
  joinWith ""
    [ "<div class=\"meter\"><span style=\"width: "
    , show percent
    , "%\"></span></div>"
    ]

renderOptionalParagraph :: String -> Maybe String -> String
renderOptionalParagraph className =
  maybe "" (\text -> "<p class=\"" <> className <> "\">" <> escape text <> "</p>")

renderLockedChip :: String -> String
renderLockedChip fragment =
  "<span class=\"fragment-chip locked\">" <> escape fragment <> "</span>"

kindLabel :: ExerciseKind -> String
kindLabel kind =
  case kind of
    MultipleChoice -> "Multiple choice"
    Cloze -> "Cloze"
    Ordering -> "Ordering"
    TrueFalse -> "True / false"

dimensionLabel :: KnowledgeDimension -> String
dimensionLabel dimension =
  case dimension of
    Recognition -> "Recognition"
    MeaningRecall -> "Meaning recall"
    FormRecall -> "Form recall"
    UseInContext -> "Use in context"
    Collocation -> "Collocation"

statusLabel :: LessonStatus -> String
statusLabel status =
  case status of
    Locked -> "Locked"
    Available -> "Ready"
    InProgress -> "In progress"
    Completed -> "Completed"

statusClassName :: LessonStatus -> String
statusClassName status =
  case status of
    Locked -> "locked"
    Available -> "available"
    InProgress -> "inprogress"
    Completed -> "completed"

initials :: String -> String
initials name =
  let
    cleaned = replaceAll (Pattern " ") (Replacement "") name
  in
    case String.take 2 cleaned of
      "" -> "RE"
      value -> escape value

escape :: String -> String
escape =
  replaceAll (Pattern "\"") (Replacement "&quot;")
    <<< replaceAll (Pattern "'") (Replacement "&#39;")
    <<< replaceAll (Pattern ">") (Replacement "&gt;")
    <<< replaceAll (Pattern "<") (Replacement "&lt;")
    <<< replaceAll (Pattern "&") (Replacement "&amp;")

escapeAttr :: String -> String
escapeAttr = escape

mapWithIndex :: forall a b. (Int -> a -> b) -> Array a -> Array b
mapWithIndex = Array.mapWithIndex
