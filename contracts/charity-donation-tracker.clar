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

;; ============================================================================
;; CROP AUDIT AND VERIFICATION SYSTEM
;; ============================================================================

;; Additional error constants for audit system
(define-constant ERR-AUDIT-NOT-FOUND (err u200))
(define-constant ERR-AUDIT-ALREADY-EXISTS (err u201))
(define-constant ERR-INVALID-AUDIT-STATUS (err u202))
(define-constant ERR-AUDIT-ALREADY-VERIFIED (err u203))
(define-constant ERR-INSUFFICIENT-AUDIT-FEE (err u204))
(define-constant ERR-AUDITOR-NOT-AUTHORIZED (err u205))

;; Audit status constants
(define-constant AUDIT-PENDING u1)
(define-constant AUDIT-IN-PROGRESS u2)
(define-constant AUDIT-COMPLETED u3)
(define-constant AUDIT-REJECTED u4)

;; Audit verification levels
(define-constant VERIFICATION-BASIC u1)
(define-constant VERIFICATION-STANDARD u2)
(define-constant VERIFICATION-PREMIUM u3)

;; Data variables for audit system
(define-data-var next-audit-id uint u1)
(define-data-var total-audit-fees uint u0)
(define-data-var audit-fee-rate uint u1000) ;; Base audit fee in micro-STX

;; Registered auditors mapping
(define-map registered-auditors
    { auditor: principal }
    {
        registration-block: uint,
        specializations: (list 10 (string-ascii 50)),
        completed-audits: uint,
        reputation-score: uint,
        is-active: bool
    }
)

;; Crop audit requests mapping
(define-map crop-audits
    { audit-id: uint }
    {
        farmer: principal,
        auditor: (optional principal),
        crop-type: (string-ascii 50),
        farm-location: (string-ascii 100),
        verification-level: uint,
        audit-fee: uint,
        status: uint,
        request-block: uint,
        completion-block: (optional uint),
        audit-report-hash: (optional (buff 32)),
        compliance-score: (optional uint)
    }
)

;; Audit results mapping
(define-map audit-results
    { audit-id: uint }
    {
        soil-quality-score: uint,
        irrigation-compliance: bool,
        pest-management-score: uint,
        sustainable-practices-score: uint,
        overall-compliance: uint,
        recommendations: (string-ascii 500),
        certification-valid-until: uint
    }
)

;; Farmer audit history mapping
(define-map farmer-audit-history
    { farmer: principal }
    { audit-ids: (list 50 uint) }
)

;; Public function to register as an auditor
(define-public (register-auditor
    (specializations (list 10 (string-ascii 50)))
)
    (begin
        ;; Check if auditor is not already registered
        (asserts! (is-none (map-get? registered-auditors { auditor: tx-sender })) ERR-AUDIT-ALREADY-EXISTS)
        
        ;; Register the auditor
        (map-set registered-auditors
            { auditor: tx-sender }
            {
                registration-block: block-height,
                specializations: specializations,
                completed-audits: u0,
                reputation-score: u100, ;; Start with base score
                is-active: true
            }
        )
        
        (ok true)
    )
)

;; Public function to request a crop audit
(define-public (request-crop-audit
    (crop-type (string-ascii 50))
    (farm-location (string-ascii 100))
    (verification-level uint)
)
    (let (
        (audit-id (var-get next-audit-id))
        (audit-fee (calculate-audit-fee verification-level))
    )
        ;; Validate verification level
        (asserts! (and (>= verification-level VERIFICATION-BASIC) (<= verification-level VERIFICATION-PREMIUM)) ERR-INVALID-AUDIT-STATUS)
        
        ;; Verify sufficient fee payment (simulated)
        (asserts! (>= audit-fee u500) ERR-INSUFFICIENT-AUDIT-FEE)
        
        ;; Create audit request
        (map-set crop-audits
            { audit-id: audit-id }
            {
                farmer: tx-sender,
                auditor: none,
                crop-type: crop-type,
                farm-location: farm-location,
                verification-level: verification-level,
                audit-fee: audit-fee,
                status: AUDIT-PENDING,
                request-block: block-height,
                completion-block: none,
                audit-report-hash: none,
                compliance-score: none
            }
        )
        
        ;; Update farmer's audit history
        (update-farmer-audit-history tx-sender audit-id)
        
        ;; Update contract state
        (var-set next-audit-id (+ audit-id u1))
        (var-set total-audit-fees (+ (var-get total-audit-fees) audit-fee))
        
        (ok audit-id)
    )
)

;; Public function for auditor to accept an audit request
(define-public (accept-audit-request (audit-id uint))
    (let (
        (audit (unwrap! (map-get? crop-audits { audit-id: audit-id }) ERR-AUDIT-NOT-FOUND))
        (auditor-info (unwrap! (map-get? registered-auditors { auditor: tx-sender }) ERR-AUDITOR-NOT-AUTHORIZED))
    )
        ;; Check auditor is active and registered
        (asserts! (get is-active auditor-info) ERR-AUDITOR-NOT-AUTHORIZED)
        
        ;; Check audit is still pending
        (asserts! (is-eq (get status audit) AUDIT-PENDING) ERR-INVALID-AUDIT-STATUS)
        
        ;; Update audit with auditor assignment
        (map-set crop-audits
            { audit-id: audit-id }
            (merge audit {
                auditor: (some tx-sender),
                status: AUDIT-IN-PROGRESS
            })
        )
        
        (ok true)
    )
)

;; Public function for auditor to submit audit results
(define-public (submit-audit-results
    (audit-id uint)
    (soil-quality-score uint)
    (irrigation-compliance bool)
    (pest-management-score uint)
    (sustainable-practices-score uint)
    (recommendations (string-ascii 500))
    (report-hash (buff 32))
)
    (let (
        (audit (unwrap! (map-get? crop-audits { audit-id: audit-id }) ERR-AUDIT-NOT-FOUND))
        (overall-score (calculate-overall-compliance soil-quality-score pest-management-score sustainable-practices-score irrigation-compliance))
        (certification-validity (+ block-height u52560)) ;; Valid for ~1 year (assuming 10min blocks)
    )
        ;; Verify auditor is assigned to this audit
        (asserts! (is-eq (some tx-sender) (get auditor audit)) ERR-AUDITOR-NOT-AUTHORIZED)
        
        ;; Check audit is in progress
        (asserts! (is-eq (get status audit) AUDIT-IN-PROGRESS) ERR-INVALID-AUDIT-STATUS)
        
        ;; Validate score ranges (0-100)
        (asserts! (and (<= soil-quality-score u100) (<= pest-management-score u100) (<= sustainable-practices-score u100)) ERR-INVALID-AUDIT-STATUS)
        
        ;; Store audit results
        (map-set audit-results
            { audit-id: audit-id }
            {
                soil-quality-score: soil-quality-score,
                irrigation-compliance: irrigation-compliance,
                pest-management-score: pest-management-score,
                sustainable-practices-score: sustainable-practices-score,
                overall-compliance: overall-score,
                recommendations: recommendations,
                certification-valid-until: certification-validity
            }
        )
        
        ;; Update audit status
        (map-set crop-audits
            { audit-id: audit-id }
            (merge audit {
                status: AUDIT-COMPLETED,
                completion-block: (some block-height),
                audit-report-hash: (some report-hash),
                compliance-score: (some overall-score)
            })
        )
        
        ;; Update auditor's completed audit count
        (update-auditor-stats tx-sender)
        
        (ok overall-score)
    )
)

;; Public function to dispute audit results (farmer only)
(define-public (dispute-audit-results (audit-id uint) (dispute-reason (string-ascii 200)))
    (let (
        (audit (unwrap! (map-get? crop-audits { audit-id: audit-id }) ERR-AUDIT-NOT-FOUND))
    )
        ;; Only the farmer who requested the audit can dispute
        (asserts! (is-eq tx-sender (get farmer audit)) ERR-NOT-AUTHORIZED)
        
        ;; Audit must be completed to be disputed
        (asserts! (is-eq (get status audit) AUDIT-COMPLETED) ERR-INVALID-AUDIT-STATUS)
        
        ;; Update audit status to rejected (simplified dispute resolution)
        (map-set crop-audits
            { audit-id: audit-id }
            (merge audit { status: AUDIT-REJECTED })
        )
        
        (ok true)
    )
)

;; Read-only function to get audit details
(define-read-only (get-audit (audit-id uint))
    (map-get? crop-audits { audit-id: audit-id })
)

;; Read-only function to get audit results
(define-read-only (get-audit-results (audit-id uint))
    (map-get? audit-results { audit-id: audit-id })
)

;; Read-only function to get auditor information
(define-read-only (get-auditor-info (auditor principal))
    (map-get? registered-auditors { auditor: auditor })
)

;; Read-only function to get farmer's audit history
(define-read-only (get-farmer-audit-history (farmer principal))
    (default-to { audit-ids: (list) } (map-get? farmer-audit-history { farmer: farmer }))
)

;; Read-only function to get audit system statistics
(define-read-only (get-audit-stats)
    {
        next-audit-id: (var-get next-audit-id),
        total-audit-fees: (var-get total-audit-fees),
        audit-fee-rate: (var-get audit-fee-rate)
    }
)

;; Read-only function to check if farmer has valid certification
(define-read-only (has-valid-certification (farmer principal))
    (let (
        (farmer-audits (get audit-ids (get-farmer-audit-history farmer)))
    )
        ;; Check if farmer has any completed audits within validity period
        (> (len (filter-valid-certifications farmer-audits)) u0)
    )
)

;; Private function to calculate audit fee based on verification level
(define-private (calculate-audit-fee (verification-level uint))
    (let (
        (base-fee (var-get audit-fee-rate))
    )
        (* base-fee verification-level) ;; Higher level = higher fee
    )
)

;; Private function to calculate overall compliance score
(define-private (calculate-overall-compliance 
    (soil-score uint) 
    (pest-score uint) 
    (sustainability-score uint) 
    (irrigation-compliance bool)
)
    (let (
        (irrigation-score (if irrigation-compliance u100 u0))
        (total-score (+ soil-score pest-score sustainability-score irrigation-score))
    )
        (/ total-score u4) ;; Average of four components
    )
)

;; Private function to update farmer's audit history
(define-private (update-farmer-audit-history (farmer principal) (audit-id uint))
    (let (
        (current-history (default-to { audit-ids: (list) } (map-get? farmer-audit-history { farmer: farmer })))
        (updated-list (unwrap! (as-max-len? (append (get audit-ids current-history) audit-id) u50) false))
    )
        (map-set farmer-audit-history
            { farmer: farmer }
            { audit-ids: updated-list }
        )
        true
    )
)

;; Private function to update auditor statistics
(define-private (update-auditor-stats (auditor principal))
    (let (
        (auditor-info (unwrap! (map-get? registered-auditors { auditor: auditor }) false))
        (new-completed-count (+ (get completed-audits auditor-info) u1))
        (new-reputation (min u200 (+ (get reputation-score auditor-info) u5))) ;; Cap at 200, gain 5 points per completion
    )
        (map-set registered-auditors
            { auditor: auditor }
            (merge auditor-info {
                completed-audits: new-completed-count,
                reputation-score: new-reputation
            })
        )
        true
    )
)

;; Private function to filter valid certifications (helper for read-only function)
(define-private (filter-valid-certifications (audit-ids (list 50 uint)))
    ;; Simplified: return all audit IDs (in real implementation would check validity dates)
    audit-ids
)
