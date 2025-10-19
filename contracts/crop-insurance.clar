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

;; Contract owner
(define-constant CONTRACT-OWNER tx-sender)

;; Policy status constants
(define-constant POLICY-ACTIVE u1)
(define-constant POLICY-EXPIRED u2)
(define-constant POLICY-CLAIMED u3)

;; Weather threshold constants (in percentage)
(define-constant RAINFALL-THRESHOLD u20) ;; 20% below normal triggers payout
(define-constant TEMPERATURE-THRESHOLD u110) ;; 110% above normal triggers payout

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
