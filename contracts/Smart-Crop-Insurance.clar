(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-AMOUNT (err u101))
(define-constant ERR-INSUFFICIENT-BALANCE (err u102))
(define-constant ERR-POLICY-EXISTS (err u103))
(define-constant ERR-NO-POLICY (err u104))
(define-constant ERR-INVALID-THRESHOLD (err u105))

(define-data-var contract-owner principal tx-sender)
(define-data-var oracle-address principal tx-sender)
(define-data-var min-premium uint u1000000)
(define-data-var payout-multiplier uint u3)

(define-map policies 
  { farmer: principal }
  {
    premium: uint,
    coverage: uint,
    rainfall-threshold: uint,
    active: bool,
    start-block: uint,
    end-block: uint
  }
)

(define-map weather-data
  { block: uint }
  { rainfall: uint }
)

(define-public (set-oracle-address (new-oracle principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (ok (var-set oracle-address new-oracle))
  )
)

(define-public (purchase-insurance (premium uint) (rainfall-threshold uint))
  (let 
    (
      (coverage (* premium (var-get payout-multiplier)))
      (policy-duration u144) ;; roughly 24 hours in blocks
    )
    (asserts! (>= premium (var-get min-premium)) ERR-INVALID-AMOUNT)
    (asserts! (> rainfall-threshold u0) ERR-INVALID-THRESHOLD)
    (asserts! (is-none (get-policy tx-sender)) ERR-POLICY-EXISTS)
    (try! (stx-transfer? premium tx-sender (as-contract tx-sender)))
    (ok (map-set policies 
      { farmer: tx-sender }
      {
        premium: premium,
        coverage: coverage,
        rainfall-threshold: rainfall-threshold,
        active: true,
        start-block: stacks-block-height,
        end-block: (+ stacks-block-height policy-duration)
      }
    ))
  )
)

(define-public (submit-weather-data (block uint) (rainfall uint))
  (begin
    (asserts! (is-eq tx-sender (var-get oracle-address)) ERR-NOT-AUTHORIZED)
    (ok (map-set weather-data { block: block } { rainfall: rainfall }))
  )
)

(define-public (claim-insurance)
  (let 
    (
      (policy (unwrap! (get-policy tx-sender) ERR-NO-POLICY))
      (current-block stacks-block-height)
    )
    (asserts! (get active policy) ERR-NO-POLICY)
    (asserts! (<= current-block (get end-block policy)) ERR-NO-POLICY)
    (asserts! (>= current-block (get start-block policy)) ERR-NO-POLICY)
    (match (get-weather-data current-block)
      weather-info (if (>= (get rainfall weather-info) (get rainfall-threshold policy))
        (begin
          (try! (as-contract (stx-transfer? (get coverage policy) tx-sender tx-sender)))
          (map-set policies 
            { farmer: tx-sender }
            (merge policy { active: false })
          )
          (ok true)
        )
        (ok false)
      )
      (ok false)
    )
  )
)

(define-read-only (get-policy (farmer principal))
  (map-get? policies { farmer: farmer })
)

(define-read-only (get-weather-data (block uint))
  (map-get? weather-data { block: block })
)
