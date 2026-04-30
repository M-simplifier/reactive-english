namespace ReactiveEnglishProof

inductive LessonStatus where
  | locked
  | available
  | inProgress
  | completed
deriving DecidableEq, Repr

def clamp (lo hi x : Int) : Int :=
  if x < lo then lo else if hi < x then hi else x

theorem clampBounds {lo hi x : Int} (h : lo ≤ hi) :
    lo ≤ clamp lo hi x ∧ clamp lo hi x ≤ hi := by
  unfold clamp
  by_cases hxLo : x < lo
  · simp [hxLo, h]
  · by_cases hHi : hi < x
    · simp [hxLo, hHi, h]
    · have hLower : lo ≤ x := Int.le_of_not_gt hxLo
      have hUpper : x ≤ hi := Int.le_of_not_gt hHi
      simp [hxLo, hHi, hLower, hUpper]

def nextMasteryPercent (currentMastery : Int) (correct : Bool) : Int :=
  clamp 0 100 (if correct then currentMastery + 25 else currentMastery - 20)

theorem nextMasteryPercentBounds (currentMastery : Int) (correct : Bool) :
    0 ≤ nextMasteryPercent currentMastery correct ∧ nextMasteryPercent currentMastery correct ≤ 100 := by
  unfold nextMasteryPercent
  exact clampBounds (by decide)

def reviewHoursForMastery (masteryPercent : Int) : Int :=
  if masteryPercent < 25 then
    4
  else if masteryPercent < 50 then
    12
  else if masteryPercent < 75 then
    24
  else if masteryPercent < 100 then
    72
  else
    168

theorem reviewHoursAllowedValues (masteryPercent : Int) :
    reviewHoursForMastery masteryPercent = 4
      ∨ reviewHoursForMastery masteryPercent = 12
      ∨ reviewHoursForMastery masteryPercent = 24
      ∨ reviewHoursForMastery masteryPercent = 72
      ∨ reviewHoursForMastery masteryPercent = 168 := by
  by_cases h₁ : masteryPercent < 25
  · simp [reviewHoursForMastery, h₁]
  · by_cases h₂ : masteryPercent < 50
    · simp [reviewHoursForMastery, h₁, h₂]
    · by_cases h₃ : masteryPercent < 75
      · simp [reviewHoursForMastery, h₁, h₂, h₃]
      · by_cases h₄ : masteryPercent < 100
        · simp [reviewHoursForMastery, h₁, h₂, h₃, h₄]
        · simp [reviewHoursForMastery, h₁, h₂, h₃, h₄]

theorem reviewHoursForMasteryMonotone {lower upper : Int}
    (h : lower ≤ upper) :
    reviewHoursForMastery lower ≤ reviewHoursForMastery upper := by
  unfold reviewHoursForMastery
  by_cases hu₁ : upper < 25
  · have hl₁ : lower < 25 := by omega
    simp [hl₁, hu₁]
  · by_cases hl₁ : lower < 25
    · by_cases hu₂ : upper < 50
      · simp [hl₁, hu₁, hu₂]
      · by_cases hu₃ : upper < 75
        · simp [hl₁, hu₁, hu₂, hu₃]
        · by_cases hu₄ : upper < 100
          · simp [hl₁, hu₁, hu₂, hu₃, hu₄]
          · simp [hl₁, hu₁, hu₂, hu₃, hu₄]
    · by_cases hu₂ : upper < 50
      · have hl₂ : lower < 50 := by omega
        simp [hl₁, hl₂, hu₁, hu₂]
      · by_cases hl₂ : lower < 50
        · by_cases hu₃ : upper < 75
          · simp [hl₁, hl₂, hu₁, hu₂, hu₃]
          · by_cases hu₄ : upper < 100
            · simp [hl₁, hl₂, hu₁, hu₂, hu₃, hu₄]
            · simp [hl₁, hl₂, hu₁, hu₂, hu₃, hu₄]
        · by_cases hu₃ : upper < 75
          · have hl₃ : lower < 75 := by omega
            simp [hl₁, hl₂, hl₃, hu₁, hu₂, hu₃]
          · by_cases hl₃ : lower < 75
            · by_cases hu₄ : upper < 100
              · simp [hl₁, hl₂, hl₃, hu₁, hu₂, hu₃, hu₄]
              · simp [hl₁, hl₂, hl₃, hu₁, hu₂, hu₃, hu₄]
            · by_cases hu₄ : upper < 100
              · have hl₄ : lower < 100 := by omega
                simp [hl₁, hl₂, hl₃, hl₄, hu₁, hu₂, hu₃, hu₄]
              · by_cases hl₄ : lower < 100
                · simp [hl₁, hl₂, hl₃, hl₄, hu₁, hu₂, hu₃, hu₄]
                · simp [hl₁, hl₂, hl₃, hl₄, hu₁, hu₂, hu₃, hu₄]

def passingAccuracy : Nat := 60

structure CompletionDecision where
  accuracyPercent : Nat
  passingAttempt : Bool
  lessonCompleted : Bool
  newlyCompleted : Bool
  bestAccuracy : Nat
  xpAwarded : Nat
deriving DecidableEq, Repr

def decideCompletion
    (alreadyCompleted : Bool)
    (previousBestAccuracy accuracyPercent correctCount totalExercises lessonXpReward : Nat) :
    CompletionDecision :=
  let passingAttempt := decide (accuracyPercent >= passingAccuracy)
  let lessonCompleted := alreadyCompleted || passingAttempt
  let newlyCompleted := (!alreadyCompleted) && passingAttempt
  let bestAccuracy := max accuracyPercent previousBestAccuracy
  let xpAwarded := (correctCount * 5) + (lessonXpReward * correctCount / max 1 totalExercises)
  { accuracyPercent
  , passingAttempt
  , lessonCompleted
  , newlyCompleted
  , bestAccuracy
  , xpAwarded
  }

theorem decideCompletionNewlyCompletedImpliesCompleted
    (alreadyCompleted : Bool)
    (previousBestAccuracy accuracyPercent correctCount totalExercises lessonXpReward : Nat) :
    (decideCompletion alreadyCompleted previousBestAccuracy accuracyPercent correctCount totalExercises lessonXpReward).newlyCompleted = true →
      (decideCompletion alreadyCompleted previousBestAccuracy accuracyPercent correctCount totalExercises lessonXpReward).lessonCompleted = true := by
  by_cases hA : alreadyCompleted = true
  · simp [decideCompletion, hA]
  · by_cases hP : accuracyPercent >= passingAccuracy
    · simp [decideCompletion, hA, hP]
    · simp [decideCompletion, hA, hP]

theorem decideCompletionAlreadyCompletedStaysCompleted
    (previousBestAccuracy accuracyPercent correctCount totalExercises lessonXpReward : Nat) :
    (decideCompletion true previousBestAccuracy accuracyPercent correctCount totalExercises lessonXpReward).lessonCompleted = true := by
  simp [decideCompletion]

theorem decideCompletionBestAccuracyDominatesInputs
    (alreadyCompleted : Bool)
    (previousBestAccuracy accuracyPercent correctCount totalExercises lessonXpReward : Nat) :
    previousBestAccuracy ≤ (decideCompletion alreadyCompleted previousBestAccuracy accuracyPercent correctCount totalExercises lessonXpReward).bestAccuracy
      ∧ accuracyPercent ≤ (decideCompletion alreadyCompleted previousBestAccuracy accuracyPercent correctCount totalExercises lessonXpReward).bestAccuracy := by
  simp [decideCompletion]
  exact ⟨Nat.le_max_right _ _, Nat.le_max_left _ _⟩

theorem decideCompletionNotPassingWithoutPreviousCompletion
    (previousBestAccuracy accuracyPercent correctCount totalExercises lessonXpReward : Nat)
    (h : accuracyPercent < passingAccuracy) :
    (decideCompletion false previousBestAccuracy accuracyPercent correctCount totalExercises lessonXpReward).lessonCompleted = false := by
  simp [decideCompletion, Nat.not_le_of_gt h]

def lessonStatusFrom (recommendedLessonId : Option String) (lessonId : String) (completed : Bool) (attemptCount : Nat) : LessonStatus :=
  if completed then
    .completed
  else if some lessonId = recommendedLessonId then
    if attemptCount > 0 then
      .inProgress
    else
      .available
  else
    .locked

theorem lessonStatusCompletedWins (recommendedLessonId : Option String) (lessonId : String) (attemptCount : Nat) :
    lessonStatusFrom recommendedLessonId lessonId true attemptCount = .completed := by
  simp [lessonStatusFrom]

theorem lessonStatusRecommendedWithoutAttempt
    (recommendedLessonId : Option String)
    (lessonId : String)
    (h : some lessonId = recommendedLessonId) :
    lessonStatusFrom recommendedLessonId lessonId false 0 = .available := by
  simp [lessonStatusFrom, h]

theorem lessonStatusRecommendedWithAttempt
    (recommendedLessonId : Option String)
    (lessonId : String)
    (attemptCount : Nat)
    (hRecommended : some lessonId = recommendedLessonId)
    (hAttempt : attemptCount > 0) :
    lessonStatusFrom recommendedLessonId lessonId false attemptCount = .inProgress := by
  simp [lessonStatusFrom, hRecommended, hAttempt]

theorem lessonStatusNonRecommendedLocked
    (recommendedLessonId : Option String)
    (lessonId : String)
    (attemptCount : Nat)
    (h : some lessonId ≠ recommendedLessonId) :
    lessonStatusFrom recommendedLessonId lessonId false attemptCount = .locked := by
  simp [lessonStatusFrom, h]

inductive CefrLevel where
  | a1
  | a2
  | b1
  | b2
  | c1
  | c2
deriving DecidableEq, Repr

def placementRank : CefrLevel → Nat
  | .a1 => 1
  | .a2 => 2
  | .b1 => 3
  | .b2 => 4
  | .c1 => 5
  | .c2 => 6

def placementXpForLevel : CefrLevel → Nat
  | .a1 => 0
  | .a2 => 240
  | .b1 => 560
  | .b2 => 980
  | .c1 => 1540
  | .c2 => 2400

def placementXpDelta (previousLevel : Option CefrLevel) (nextLevel : CefrLevel) : Nat :=
  placementXpForLevel nextLevel -
    match previousLevel with
    | none => 0
    | some previous => placementXpForLevel previous

def shouldCompleteLessonForPlacement (placementLevel lessonLevel : CefrLevel) : Bool :=
  decide (placementRank lessonLevel < placementRank placementLevel)

theorem placementRankPositive (level : CefrLevel) :
    0 < placementRank level := by
  cases level <;> simp [placementRank]

theorem placementXpForLevelNonnegative (level : CefrLevel) :
    0 ≤ placementXpForLevel level := by
  exact Nat.zero_le _

theorem placementXpForLevelMonotone {lower upper : CefrLevel}
    (h : placementRank lower ≤ placementRank upper) :
    placementXpForLevel lower ≤ placementXpForLevel upper := by
  cases lower <;> cases upper <;> simp [placementRank, placementXpForLevel] at h ⊢

theorem placementXpDeltaNonnegative (previousLevel : Option CefrLevel) (nextLevel : CefrLevel) :
    0 ≤ placementXpDelta previousLevel nextLevel := by
  exact Nat.zero_le _

theorem placementXpDeltaZeroWhenPriorAtLeast
    (previousLevel nextLevel : CefrLevel)
    (h : placementXpForLevel nextLevel ≤ placementXpForLevel previousLevel) :
    placementXpDelta (some previousLevel) nextLevel = 0 := by
  unfold placementXpDelta
  exact Nat.sub_eq_zero_of_le h

theorem placementCompletesOnlyLowerRank
    (placementLevel lessonLevel : CefrLevel) :
    shouldCompleteLessonForPlacement placementLevel lessonLevel = true →
      placementRank lessonLevel < placementRank placementLevel := by
  unfold shouldCompleteLessonForPlacement
  intro h
  exact of_decide_eq_true h

inductive GoogleEmailVerified where
  | missing
  | unverified
  | verified
deriving DecidableEq, Repr

def googleEmailAccepted : GoogleEmailVerified → Bool
  | .verified => true
  | .unverified => false
  | .missing => false

def googleExpiryAccepted (now : Nat) (expiresAt : Option Nat) : Bool :=
  match expiresAt with
  | none => true
  | some expiry => decide (now ≤ expiry)

theorem googleExpiryRejectsPast (now expiry : Nat) (h : expiry < now) :
    googleExpiryAccepted now (some expiry) = false := by
  simp [googleExpiryAccepted, Nat.not_le_of_gt h]

theorem googleExpiryAcceptsFutureOrPresent (now expiry : Nat) (h : now ≤ expiry) :
    googleExpiryAccepted now (some expiry) = true := by
  simp [googleExpiryAccepted, h]

def googleTokenAccepted
    (issuerAccepted audienceAccepted expiryAccepted : Bool)
    (emailVerified : GoogleEmailVerified) :
    Bool :=
  issuerAccepted && audienceAccepted && expiryAccepted && googleEmailAccepted emailVerified

theorem googleTokenAcceptedImpliesCriticalChecks
    (issuerAccepted audienceAccepted expiryAccepted : Bool)
    (emailVerified : GoogleEmailVerified) :
    googleTokenAccepted issuerAccepted audienceAccepted expiryAccepted emailVerified = true →
      issuerAccepted = true
        ∧ audienceAccepted = true
        ∧ expiryAccepted = true
        ∧ emailVerified = .verified := by
  cases issuerAccepted <;> cases audienceAccepted <;> cases expiryAccepted <;> cases emailVerified <;>
    simp [googleTokenAccepted, googleEmailAccepted]

theorem googleTokenRejectsMissingEmailVerification
    (issuerAccepted audienceAccepted expiryAccepted : Bool) :
    googleTokenAccepted issuerAccepted audienceAccepted expiryAccepted .missing = false := by
  cases issuerAccepted <;> cases audienceAccepted <;> cases expiryAccepted <;>
    simp [googleTokenAccepted, googleEmailAccepted]

theorem googleTokenRejectsUnverifiedEmail
    (issuerAccepted audienceAccepted expiryAccepted : Bool) :
    googleTokenAccepted issuerAccepted audienceAccepted expiryAccepted .unverified = false := by
  cases issuerAccepted <;> cases audienceAccepted <;> cases expiryAccepted <;>
    simp [googleTokenAccepted, googleEmailAccepted]

theorem googleTokenRejectsAudienceMismatch
    (issuerAccepted expiryAccepted : Bool)
    (emailVerified : GoogleEmailVerified) :
    googleTokenAccepted issuerAccepted false expiryAccepted emailVerified = false := by
  cases issuerAccepted <;> cases expiryAccepted <;> cases emailVerified <;>
    simp [googleTokenAccepted, googleEmailAccepted]

theorem googleTokenRejectsBadIssuer
    (audienceAccepted expiryAccepted : Bool)
    (emailVerified : GoogleEmailVerified) :
    googleTokenAccepted false audienceAccepted expiryAccepted emailVerified = false := by
  cases audienceAccepted <;> cases expiryAccepted <;> cases emailVerified <;>
    simp [googleTokenAccepted, googleEmailAccepted]

inductive LastActiveRelation where
  | missingOrInvalid
  | sameDay
  | yesterday
  | gapOrFuture
deriving DecidableEq, Repr

def advanceStreakModel (relation : LastActiveRelation) (currentStreak : Nat) : Nat :=
  match relation with
  | .missingOrInvalid => 1
  | .sameDay => max 1 currentStreak
  | .yesterday => max 1 currentStreak + 1
  | .gapOrFuture => 1

theorem advanceStreakAtLeastOne (relation : LastActiveRelation) (currentStreak : Nat) :
    1 ≤ advanceStreakModel relation currentStreak := by
  cases relation
  · simp [advanceStreakModel]
  · simp [advanceStreakModel]
    exact Nat.le_max_left 1 currentStreak
  · simp [advanceStreakModel]
  · simp [advanceStreakModel]

theorem advanceStreakYesterdayIncreasesFromAtLeastOne (currentStreak : Nat) :
    currentStreak + 1 ≤ advanceStreakModel .yesterday currentStreak := by
  simp [advanceStreakModel]
  omega

def validPresentedOrderingFragments (canonical presented : List String) : Prop :=
  presented.Perm canonical

def nonCanonicalOrderingPresentation (canonical presented : List String) : Prop :=
  presented ≠ canonical

theorem orderingFragmentPermutationPreservesLength
    {canonical presented : List String}
    (h : validPresentedOrderingFragments canonical presented) :
    presented.length = canonical.length := by
  exact List.Perm.length_eq h

theorem orderingFragmentPermutationPreservesMembership
    {canonical presented : List String}
    (h : validPresentedOrderingFragments canonical presented)
    {fragment : String} :
    fragment ∈ presented ↔ fragment ∈ canonical := by
  exact List.Perm.mem_iff h

theorem nonCanonicalOrderingPresentationRejectsOriginalOrder
    {canonical presented : List String}
    (h : nonCanonicalOrderingPresentation canonical presented) :
    presented = canonical → False := by
  intro sameOrder
  exact h sameOrder

inductive KnowledgeDimension where
  | recognition
  | meaningRecall
  | formRecall
  | useInContext
  | collocation
deriving DecidableEq, Repr

def nextVocabularyMasteryPercent (currentMastery : Int) (correct : Bool) : Int :=
  clamp 0 100 (if correct then currentMastery + 18 else currentMastery - 12)

theorem nextVocabularyMasteryPercentBounds (currentMastery : Int) (correct : Bool) :
    0 ≤ nextVocabularyMasteryPercent currentMastery correct ∧ nextVocabularyMasteryPercent currentMastery correct ≤ 100 := by
  unfold nextVocabularyMasteryPercent
  exact clampBounds (by decide)

def vocabularyReviewHours (masteryPercent : Int) : Int :=
  if masteryPercent < 20 then
    6
  else if masteryPercent < 45 then
    18
  else if masteryPercent < 70 then
    48
  else if masteryPercent < 90 then
    96
  else
    240

theorem vocabularyReviewHoursAllowedValues (masteryPercent : Int) :
    vocabularyReviewHours masteryPercent = 6
      ∨ vocabularyReviewHours masteryPercent = 18
      ∨ vocabularyReviewHours masteryPercent = 48
      ∨ vocabularyReviewHours masteryPercent = 96
      ∨ vocabularyReviewHours masteryPercent = 240 := by
  by_cases h₁ : masteryPercent < 20
  · simp [vocabularyReviewHours, h₁]
  · by_cases h₂ : masteryPercent < 45
    · simp [vocabularyReviewHours, h₁, h₂]
    · by_cases h₃ : masteryPercent < 70
      · simp [vocabularyReviewHours, h₁, h₂, h₃]
      · by_cases h₄ : masteryPercent < 90
        · simp [vocabularyReviewHours, h₁, h₂, h₃, h₄]
        · simp [vocabularyReviewHours, h₁, h₂, h₃, h₄]

theorem vocabularyReviewHoursMonotone {lower upper : Int}
    (h : lower ≤ upper) :
    vocabularyReviewHours lower ≤ vocabularyReviewHours upper := by
  unfold vocabularyReviewHours
  by_cases hu₁ : upper < 20
  · have hl₁ : lower < 20 := by omega
    simp [hl₁, hu₁]
  · by_cases hl₁ : lower < 20
    · by_cases hu₂ : upper < 45
      · simp [hl₁, hu₁, hu₂]
      · by_cases hu₃ : upper < 70
        · simp [hl₁, hu₁, hu₂, hu₃]
        · by_cases hu₄ : upper < 90
          · simp [hl₁, hu₁, hu₂, hu₃, hu₄]
          · simp [hl₁, hu₁, hu₂, hu₃, hu₄]
    · by_cases hu₂ : upper < 45
      · have hl₂ : lower < 45 := by omega
        simp [hl₁, hl₂, hu₁, hu₂]
      · by_cases hl₂ : lower < 45
        · by_cases hu₃ : upper < 70
          · simp [hl₁, hl₂, hu₁, hu₂, hu₃]
          · by_cases hu₄ : upper < 90
            · simp [hl₁, hl₂, hu₁, hu₂, hu₃, hu₄]
            · simp [hl₁, hl₂, hu₁, hu₂, hu₃, hu₄]
        · by_cases hu₃ : upper < 70
          · have hl₃ : lower < 70 := by omega
            simp [hl₁, hl₂, hl₃, hu₁, hu₂, hu₃]
          · by_cases hl₃ : lower < 70
            · by_cases hu₄ : upper < 90
              · simp [hl₁, hl₂, hl₃, hu₁, hu₂, hu₃, hu₄]
              · simp [hl₁, hl₂, hl₃, hu₁, hu₂, hu₃, hu₄]
            · by_cases hu₄ : upper < 90
              · have hl₄ : lower < 90 := by omega
                simp [hl₁, hl₂, hl₃, hl₄, hu₁, hu₂, hu₃, hu₄]
              · by_cases hl₄ : lower < 90
                · simp [hl₁, hl₂, hl₃, hl₄, hu₁, hu₂, hu₃, hu₄]
                · simp [hl₁, hl₂, hl₃, hl₄, hu₁, hu₂, hu₃, hu₄]

def vocabularyDimensionXpDelta : KnowledgeDimension → Nat
  | .recognition => 2
  | .meaningRecall => 2
  | .formRecall => 3
  | .useInContext => 3
  | .collocation => 3

theorem vocabularyDimensionXpDeltaPositive (dimension : KnowledgeDimension) :
    0 < vocabularyDimensionXpDelta dimension := by
  cases dimension <;> simp [vocabularyDimensionXpDelta]

end ReactiveEnglishProof
