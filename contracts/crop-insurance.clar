;; title: Smart Crop Insurance Contract
;; version: 1.0.0
;; summary: Decentralized crop insurance system with weather-based payouts
;; description: Smart contract for managing crop insurance policies, premiums, and automated claims

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-POLICY-NOT-FOUND (err u101))
(define-constant ERR-POLICY-ALREADY-EXISTS (err u102))
(define-constant ERR-INSUFFICIENT-PREMIUM (err u103))
(define-constant ERR-POLICY-EXPIRED (err u104))
(define-constant ERR-POLICY-NOT-ACTIVE (err u105))
(define-constant ERR-INVALID-WEATHER-DATA (err u106))
(define-constant ERR-CLAIM-ALREADY-PROCESSED (err u107))
(define-constant ERR-INSUFFICIENT-FUNDS (err u108))
(define-constant ERR-RISK-ASSESSMENT-NOT-FOUND (err u109))
(define-constant ERR-INVALID-RISK-LEVEL (err u110))

;; Contract owner
(define-constant CONTRACT-OWNER tx-sender)

;; Policy status constants
(define-constant POLICY-ACTIVE u1)
(define-constant POLICY-EXPIRED u2)
(define-constant POLICY-CLAIMED u3)

;; Weather threshold constants (in percentage)
(define-constant RAINFALL-THRESHOLD u20) ;; 20% below normal triggers payout
(define-constant TEMPERATURE-THRESHOLD u110) ;; 110% above normal triggers payout

;; Risk assessment constants
(define-constant RISK-LOW u1)
(define-constant RISK-MEDIUM u2)
(define-constant RISK-HIGH u3)
(define-constant RISK-EXTREME u4)

;; Premium multipliers for risk levels (in basis points - 10000 = 100%)
(define-constant RISK-MULTIPLIER-LOW u8000)    ;; 80% of base premium
(define-constant RISK-MULTIPLIER-MEDIUM u10000) ;; 100% of base premium
(define-constant RISK-MULTIPLIER-HIGH u13000)   ;; 130% of base premium
(define-constant RISK-MULTIPLIER-EXTREME u16000) ;; 160% of base premium

;; Data variables
(define-data-var next-policy-id uint u1)
(define-data-var total-premium-pool uint u0)
(define-data-var oracle-address (optional principal) none)

;; Policy structure
(define-map policies
    { policy-id: uint }
    {
        farmer: principal,
        crop-type: (string-ascii 50),
        coverage-amount: uint,
        premium-paid: uint,
        start-block: uint,
        end-block: uint,
        status: uint,
        region: (string-ascii 100)
    }
)

;; Weather data structure for claims
(define-map weather-claims
    { policy-id: uint }
    {
        rainfall-percentage: uint,
        temperature-percentage: uint,
        reported-block: uint,
        payout-amount: uint,
        processed: bool
    }
)

;; Farmer policy tracking
(define-map farmer-policies
    { farmer: principal }
    { policy-ids: (list 100 uint) }
)

;; Regional statistics
(define-map regional-stats
    { region: (string-ascii 100) }
    {
        total-policies: uint,
        total-coverage: uint,
        total-claims: uint,
        total-payouts: uint
    }
)

;; Risk assessment data for regions and crop types
(define-map risk-assessments
    { region: (string-ascii 100), crop-type: (string-ascii 50) }
    {
        risk-level: uint,
        historical-claims: uint,
        success-rate: uint,
        last-updated: uint,
        assessment-period: uint
    }
)

;; Risk factor tracking for dynamic adjustments
(define-map risk-factors
    { region: (string-ascii 100) }
    {
        weather-volatility: uint,
        climate-trend: uint,
        soil-quality: uint,
        water-availability: uint,
        last-assessment: uint
    }
)

;; Public function to set oracle address (only contract owner)
(define-public (set-oracle (oracle principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (ok (var-set oracle-address (some oracle)))
    )
)

;; Public function to create a new crop insurance policy
(define-public (create-policy 
    (crop-type (string-ascii 50))
    (coverage-amount uint)
    (duration-blocks uint)
    (region (string-ascii 100))
)
    (let (
        (policy-id (var-get next-policy-id))
        (premium (calculate-premium coverage-amount duration-blocks))
        (end-block (+ block-height duration-blocks))
    )
        ;; Check if policy already exists for this farmer
        (asserts! (is-none (map-get? policies { policy-id: policy-id })) ERR-POLICY-ALREADY-EXISTS)
        
        ;; Verify sufficient premium payment (simulated - in real implementation would check STX transfer)
        (asserts! (>= premium u1000) ERR-INSUFFICIENT-PREMIUM)
        
        ;; Create the policy
        (map-set policies
            { policy-id: policy-id }
            {
                farmer: tx-sender,
                crop-type: crop-type,
                coverage-amount: coverage-amount,
                premium-paid: premium,
                start-block: block-height,
                end-block: end-block,
                status: POLICY-ACTIVE,
                region: region
            }
        )
        
        ;; Update farmer's policy list
        (update-farmer-policies tx-sender policy-id)
        
        ;; Update regional statistics
        (update-regional-stats region coverage-amount u0 u0)
        
        ;; Update contract state
        (var-set next-policy-id (+ policy-id u1))
        (var-set total-premium-pool (+ (var-get total-premium-pool) premium))
        
        (ok policy-id)
    )
)

;; Public function to submit weather data and process claim (oracle only)
(define-public (submit-weather-claim
    (policy-id uint)
    (rainfall-percentage uint)
    (temperature-percentage uint)
)
    (let (
        (policy (unwrap! (map-get? policies { policy-id: policy-id }) ERR-POLICY-NOT-FOUND))
        (oracle (unwrap! (var-get oracle-address) ERR-NOT-AUTHORIZED))
    )
        ;; Only oracle can submit weather data
        (asserts! (is-eq tx-sender oracle) ERR-NOT-AUTHORIZED)
        
        ;; Check policy is active and not expired
        (asserts! (is-eq (get status policy) POLICY-ACTIVE) ERR-POLICY-NOT-ACTIVE)
        (asserts! (< block-height (get end-block policy)) ERR-POLICY-EXPIRED)
        
        ;; Check if claim already processed
        (asserts! (is-none (map-get? weather-claims { policy-id: policy-id })) ERR-CLAIM-ALREADY-PROCESSED)
        
        ;; Validate weather data
        (asserts! (and (<= rainfall-percentage u200) (<= temperature-percentage u200)) ERR-INVALID-WEATHER-DATA)
        
        (let (
            (payout-amount (calculate-payout policy rainfall-percentage temperature-percentage))
        )
            ;; Record weather claim
            (map-set weather-claims
                { policy-id: policy-id }
                {
                    rainfall-percentage: rainfall-percentage,
                    temperature-percentage: temperature-percentage,
                    reported-block: block-height,
                    payout-amount: payout-amount,
                    processed: (> payout-amount u0)
                }
            )
            
            ;; If payout is due, update policy status and regional stats
            (if (> payout-amount u0)
                (begin
                    (map-set policies
                        { policy-id: policy-id }
                        (merge policy { status: POLICY-CLAIMED })
                    )
                    (update-regional-stats (get region policy) u0 u1 payout-amount)
                )
                true
            )
            
            (ok payout-amount)
        )
    )
)

;; Public function to renew an existing policy
(define-public (renew-policy
    (policy-id uint)
    (additional-duration uint)
)
    (let (
        (policy (unwrap! (map-get? policies { policy-id: policy-id }) ERR-POLICY-NOT-FOUND))
        (additional-premium (calculate-premium (get coverage-amount policy) additional-duration))
    )
        ;; Only policy owner can renew
        (asserts! (is-eq tx-sender (get farmer policy)) ERR-NOT-AUTHORIZED)
        
        ;; Policy must be active
        (asserts! (is-eq (get status policy) POLICY-ACTIVE) ERR-POLICY-NOT-ACTIVE)
        
        ;; Update policy with extended duration
        (map-set policies
            { policy-id: policy-id }
            (merge policy {
                end-block: (+ (get end-block policy) additional-duration),
                premium-paid: (+ (get premium-paid policy) additional-premium)
            })
        )
        
        ;; Update premium pool
        (var-set total-premium-pool (+ (var-get total-premium-pool) additional-premium))
        
        (ok true)
    )
)

;; Read-only function to get policy details
(define-read-only (get-policy (policy-id uint))
    (map-get? policies { policy-id: policy-id })
)

;; Read-only function to get weather claim details
(define-read-only (get-weather-claim (policy-id uint))
    (map-get? weather-claims { policy-id: policy-id })
)

;; Read-only function to get farmer's policies
(define-read-only (get-farmer-policies (farmer principal))
    (default-to { policy-ids: (list) } (map-get? farmer-policies { farmer: farmer }))
)

;; Read-only function to get regional statistics
(define-read-only (get-regional-stats (region (string-ascii 100)))
    (default-to 
        { total-policies: u0, total-coverage: u0, total-claims: u0, total-payouts: u0 }
        (map-get? regional-stats { region: region })
    )
)

;; Read-only function to get contract statistics
(define-read-only (get-contract-stats)
    {
        next-policy-id: (var-get next-policy-id),
        total-premium-pool: (var-get total-premium-pool),
        oracle-address: (var-get oracle-address)
    }
)

;; Read-only function to check if policy qualifies for payout
(define-read-only (check-payout-eligibility
    (policy-id uint)
    (rainfall-percentage uint)
    (temperature-percentage uint)
)
    (let (
        (policy (unwrap! (map-get? policies { policy-id: policy-id }) ERR-POLICY-NOT-FOUND))
    )
        (ok (calculate-payout policy rainfall-percentage temperature-percentage))
    )
)

;; Private function to calculate premium based on coverage and duration
(define-private (calculate-premium (coverage uint) (duration uint))
    ;; Simple premium calculation: 5% of coverage + duration factor
    (+ (/ (* coverage u5) u100) (/ duration u1000))
)

;; Public function to update risk assessment for a region and crop type
(define-public (update-risk-assessment
    (region (string-ascii 100))
    (crop-type (string-ascii 50))
    (risk-level uint)
    (historical-claims uint)
    (success-rate uint)
    (assessment-period uint)
)
    (begin
        ;; Only contract owner can update risk assessments
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        
        ;; Validate risk level
        (asserts! (and (>= risk-level RISK-LOW) (<= risk-level RISK-EXTREME)) ERR-INVALID-RISK-LEVEL)
        
        ;; Validate success rate (0-100%)
        (asserts! (<= success-rate u100) ERR-INVALID-RISK-LEVEL)
        
        ;; Update risk assessment
        (map-set risk-assessments
            { region: region, crop-type: crop-type }
            {
                risk-level: risk-level,
                historical-claims: historical-claims,
                success-rate: success-rate,
                last-updated: block-height,
                assessment-period: assessment-period
            }
        )
        
        (ok true)
    )
)

;; Public function to update regional risk factors
(define-public (update-risk-factors
    (region (string-ascii 100))
    (weather-volatility uint)
    (climate-trend uint)
    (soil-quality uint)
    (water-availability uint)
)
    (begin
        ;; Only contract owner can update risk factors
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        
        ;; Validate risk factors (0-100 scale)
        (asserts! (and 
            (<= weather-volatility u100)
            (<= climate-trend u100)
            (<= soil-quality u100)
            (<= water-availability u100)
        ) ERR-INVALID-RISK-LEVEL)
        
        ;; Update risk factors
        (map-set risk-factors
            { region: region }
            {
                weather-volatility: weather-volatility,
                climate-trend: climate-trend,
                soil-quality: soil-quality,
                water-availability: water-availability,
                last-assessment: block-height
            }
        )
        
        (ok true)
    )
)

;; Public function to calculate risk-adjusted premium
(define-public (calculate-risk-adjusted-premium
    (coverage uint)
    (duration uint)
    (region (string-ascii 100))
    (crop-type (string-ascii 50))
)
    (let (
        (base-premium (calculate-premium coverage duration))
        (risk-data (map-get? risk-assessments { region: region, crop-type: crop-type }))
        (regional-factors (map-get? risk-factors { region: region }))
    )
        (match risk-data
            risk-assessment
            (let (
                (risk-multiplier (get-risk-multiplier (get risk-level risk-assessment)))
                (adjusted-premium (/ (* base-premium risk-multiplier) u10000))
                (factor-adjustment (match regional-factors
                    factors (calculate-factor-adjustment factors)
                    u10000 ;; No adjustment if no factors found
                ))
                (final-premium (/ (* adjusted-premium factor-adjustment) u10000))
            )
                (ok final-premium)
            )
            (ok base-premium) ;; Return base premium if no risk data found
        )
    )
)

;; Read-only function to get risk assessment
(define-read-only (get-risk-assessment (region (string-ascii 100)) (crop-type (string-ascii 50)))
    (map-get? risk-assessments { region: region, crop-type: crop-type })
)

;; Read-only function to get regional risk factors
(define-read-only (get-risk-factors (region (string-ascii 100)))
    (map-get? risk-factors { region: region })
)

;; Read-only function to get comprehensive risk profile
(define-read-only (get-risk-profile (region (string-ascii 100)) (crop-type (string-ascii 50)))
    (let (
        (assessment (map-get? risk-assessments { region: region, crop-type: crop-type }))
        (factors (map-get? risk-factors { region: region }))
        (regional-stats (get-regional-stats region))
    )
        {
            assessment: assessment,
            factors: factors,
            regional-stats: regional-stats,
            risk-score: (calculate-composite-risk-score assessment factors regional-stats)
        }
    )
)

;; Private function to get risk multiplier based on risk level
(define-private (get-risk-multiplier (risk-level uint))
    (if (is-eq risk-level RISK-LOW)
        RISK-MULTIPLIER-LOW
        (if (is-eq risk-level RISK-MEDIUM)
            RISK-MULTIPLIER-MEDIUM
            (if (is-eq risk-level RISK-HIGH)
                RISK-MULTIPLIER-HIGH
                RISK-MULTIPLIER-EXTREME
            )
        )
    )
)

;; Private function to calculate factor-based adjustment
(define-private (calculate-factor-adjustment (factors { weather-volatility: uint, climate-trend: uint, soil-quality: uint, water-availability: uint, last-assessment: uint }))
    (let (
        (weather-factor (/ (* (get weather-volatility factors) u50) u100)) ;; Max 50% increase
        (climate-factor (/ (* (get climate-trend factors) u30) u100))     ;; Max 30% increase
        (soil-factor (- u10000 (/ (* (get soil-quality factors) u20) u100))) ;; Up to 20% discount for good soil
        (water-factor (- u10000 (/ (* (get water-availability factors) u25) u100))) ;; Up to 25% discount for good water
        (total-adjustment (+ u10000 weather-factor climate-factor (- soil-factor u10000) (- water-factor u10000)))
    )
        ;; Cap adjustment between 70% and 180%
        (if (< total-adjustment u7000)
            u7000
            (if (> total-adjustment u18000)
                u18000
                total-adjustment
            )
        )
    )
)

;; Private function to calculate composite risk score (0-100)
(define-private (calculate-composite-risk-score 
    (assessment (optional { risk-level: uint, historical-claims: uint, success-rate: uint, last-updated: uint, assessment-period: uint }))
    (factors (optional { weather-volatility: uint, climate-trend: uint, soil-quality: uint, water-availability: uint, last-assessment: uint }))
    (stats { total-policies: uint, total-coverage: uint, total-claims: uint, total-payouts: uint })
)
    (let (
        (base-score (match assessment
            data (* (get risk-level data) u20) ;; Risk level contributes 20-80 points
            u50 ;; Default moderate risk if no data
        ))
        (success-adjustment (match assessment
            data (- u50 (/ (get success-rate data) u2)) ;; Success rate reduces risk
            u0
        ))
        (claims-ratio (if (> (get total-policies stats) u0)
            (/ (* (get total-claims stats) u100) (get total-policies stats))
            u0
        ))
        (historical-adjustment (/ claims-ratio u5)) ;; Historical claims increase risk
        (factor-score (match factors
            data (/ (+ (get weather-volatility data) (get climate-trend data) 
                      (- u100 (get soil-quality data)) (- u100 (get water-availability data))) u4)
            u25 ;; Default moderate environmental risk
        ))
        (composite (+ base-score success-adjustment historical-adjustment factor-score))
    )
        ;; Cap score between 0 and 100
        (if (> composite u100) u100 (if (< composite u0) u0 composite))
    )
)

;; Private function to calculate payout based on weather conditions
(define-private (calculate-payout 
    (policy { farmer: principal, crop-type: (string-ascii 50), coverage-amount: uint, premium-paid: uint, start-block: uint, end-block: uint, status: uint, region: (string-ascii 100) })
    (rainfall-percentage uint)
    (temperature-percentage uint)
)
    (let (
        (coverage (get coverage-amount policy))
        (rainfall-trigger (< rainfall-percentage RAINFALL-THRESHOLD))
        (temperature-trigger (> temperature-percentage TEMPERATURE-THRESHOLD))
    )
        (if (or rainfall-trigger temperature-trigger)
            ;; Calculate payout percentage based on severity
            (if rainfall-trigger
                (/ (* coverage (- RAINFALL-THRESHOLD rainfall-percentage)) u20) ;; Up to 100% payout for 0% rainfall
                (/ (* coverage (- temperature-percentage u100)) u10) ;; Up to 100% payout for 200% temperature
            )
            u0 ;; No payout if conditions are within normal range
        )
    )
)

;; Private function to update farmer's policy list
(define-private (update-farmer-policies (farmer principal) (policy-id uint))
    (let (
        (current-policies (default-to { policy-ids: (list) } (map-get? farmer-policies { farmer: farmer })))
        (updated-list (unwrap! (as-max-len? (append (get policy-ids current-policies) policy-id) u100) false))
    )
        (map-set farmer-policies
            { farmer: farmer }
            { policy-ids: updated-list }
        )
        true
    )
)

;; Private function to update regional statistics
(define-private (update-regional-stats 
    (region (string-ascii 100))
    (coverage-delta uint)
    (claims-delta uint)
    (payouts-delta uint)
)
    (let (
        (current-stats (default-to 
            { total-policies: u0, total-coverage: u0, total-claims: u0, total-payouts: u0 }
            (map-get? regional-stats { region: region })
        ))
    )
        (map-set regional-stats
            { region: region }
            {
                total-policies: (+ (get total-policies current-stats) u1),
                total-coverage: (+ (get total-coverage current-stats) coverage-delta),
                total-claims: (+ (get total-claims current-stats) claims-delta),
                total-payouts: (+ (get total-payouts current-stats) payouts-delta)
            }
        )
        true
    )
)
