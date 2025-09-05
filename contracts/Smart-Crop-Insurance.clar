(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-AMOUNT (err u101))
(define-constant ERR-INSUFFICIENT-BALANCE (err u102))
(define-constant ERR-POLICY-EXISTS (err u103))
(define-constant ERR-NO-POLICY (err u104))
(define-constant ERR-INVALID-THRESHOLD (err u105))
(define-constant ERR-INSUFFICIENT-POOL-BALANCE (err u108))
(define-constant ERR-NO-STAKE (err u109))
(define-constant ERR-POLICY-NOT-TRANSFERABLE (err u110))
(define-constant ERR-INVALID-RECIPIENT (err u111))
(define-constant ERR-POLICY-EXPIRED (err u112))
(define-constant ERR-RENEWAL-NOT-ENABLED (err u113))
(define-constant ERR-INSUFFICIENT-BALANCE-FOR-RENEWAL (err u114))

(define-data-var contract-owner principal tx-sender)
(define-data-var oracle-address principal tx-sender)
(define-data-var min-premium uint u1000000)
(define-data-var payout-multiplier uint u3)
(define-data-var total-pool-balance uint u0)
(define-data-var total-shares uint u0)
(define-data-var yield-rate uint u5)

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

(define-map liquidity-providers
  { provider: principal }
  {
    staked-amount: uint,
    shares: uint,
    last-claim-block: uint
  }
)

(define-map weather-data
  { block: uint }
  { rainfall: uint }
)

(define-map policy-transfers
  { farmer: principal }
  {
    recipient: principal,
    transfer-price: uint,
    confirmed: bool
  }
)

(define-map auto-renewals
  { farmer: principal }
  {
    enabled: bool,
    max-premium: uint,
    renewal-count: uint
  }
)

(define-public (set-oracle-address (new-oracle principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (ok (var-set oracle-address new-oracle))
  )
)

(define-public (stake-in-pool (amount uint))
  (let
    (
      (current-stake (default-to { staked-amount: u0, shares: u0, last-claim-block: u0 } 
                      (map-get? liquidity-providers { provider: tx-sender })))
      (total-pool (var-get total-pool-balance))
      (total-supply (var-get total-shares))
      (new-shares (if (is-eq total-supply u0) 
                     amount 
                     (/ (* amount total-supply) total-pool)))
    )
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (map-set liquidity-providers
      { provider: tx-sender }
      {
        staked-amount: (+ (get staked-amount current-stake) amount),
        shares: (+ (get shares current-stake) new-shares),
        last-claim-block: stacks-block-height
      }
    )
    (var-set total-pool-balance (+ total-pool amount))
    (var-set total-shares (+ total-supply new-shares))
    (ok new-shares)
  )
)

(define-public (unstake-from-pool (shares-to-burn uint))
  (let
    (
      (stake-info (unwrap! (map-get? liquidity-providers { provider: tx-sender }) ERR-NO-STAKE))
      (total-pool (var-get total-pool-balance))
      (total-supply (var-get total-shares))
      (withdrawal-amount (/ (* shares-to-burn total-pool) total-supply))
    )
    (asserts! (> shares-to-burn u0) ERR-INVALID-AMOUNT)
    (asserts! (<= shares-to-burn (get shares stake-info)) ERR-INSUFFICIENT-BALANCE)
    (asserts! (>= total-pool withdrawal-amount) ERR-INSUFFICIENT-POOL-BALANCE)
    (try! (as-contract (stx-transfer? withdrawal-amount tx-sender tx-sender)))
    (map-set liquidity-providers
      { provider: tx-sender }
      {
        staked-amount: (- (get staked-amount stake-info) withdrawal-amount),
        shares: (- (get shares stake-info) shares-to-burn),
        last-claim-block: (get last-claim-block stake-info)
      }
    )
    (var-set total-pool-balance (- total-pool withdrawal-amount))
    (var-set total-shares (- total-supply shares-to-burn))
    (ok withdrawal-amount)
  )
)

(define-public (claim-yield)
  (let
    (
      (stake-info (unwrap! (map-get? liquidity-providers { provider: tx-sender }) ERR-NO-STAKE))
      (blocks-elapsed (- stacks-block-height (get last-claim-block stake-info)))
      (yield-amount (/ (* (get staked-amount stake-info) (var-get yield-rate) blocks-elapsed) u100000))
    )
    (asserts! (> blocks-elapsed u0) ERR-INVALID-AMOUNT)
    (asserts! (>= (var-get total-pool-balance) yield-amount) ERR-INSUFFICIENT-POOL-BALANCE)
    (try! (as-contract (stx-transfer? yield-amount tx-sender tx-sender)))
    (map-set liquidity-providers
      { provider: tx-sender }
      (merge stake-info { last-claim-block: stacks-block-height })
    )
    (var-set total-pool-balance (- (var-get total-pool-balance) yield-amount))
    (ok yield-amount)
  )
)

(define-public (purchase-insurance (premium uint) (rainfall-threshold uint))
  (let 
    (
      (coverage (* premium (var-get payout-multiplier)))
      (policy-duration u144)
    )
    (asserts! (>= premium (var-get min-premium)) ERR-INVALID-AMOUNT)
    (asserts! (> rainfall-threshold u0) ERR-INVALID-THRESHOLD)
    (asserts! (is-none (get-policy tx-sender)) ERR-POLICY-EXISTS)
    (asserts! (>= (var-get total-pool-balance) coverage) ERR-INSUFFICIENT-POOL-BALANCE)
    (try! (stx-transfer? premium tx-sender (as-contract tx-sender)))
    (var-set total-pool-balance (+ (var-get total-pool-balance) premium))
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
          (var-set total-pool-balance (- (var-get total-pool-balance) (get coverage policy)))
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

(define-read-only (get-stake-info (provider principal))
  (map-get? liquidity-providers { provider: provider })
)

(define-read-only (get-pool-stats)
  {
    total-balance: (var-get total-pool-balance),
    total-shares: (var-get total-shares),
    yield-rate: (var-get yield-rate)
  }
)

(define-read-only (get-weather-data (block uint))
  (map-get? weather-data { block: block })
)

(define-public (initiate-policy-transfer (recipient principal) (transfer-price uint))
  (let
    (
      (policy (unwrap! (get-policy tx-sender) ERR-NO-POLICY))
      (current-block stacks-block-height)
    )
    (asserts! (get active policy) ERR-POLICY-NOT-TRANSFERABLE)
    (asserts! (> (get end-block policy) current-block) ERR-POLICY-EXPIRED)
    (asserts! (not (is-eq tx-sender recipient)) ERR-INVALID-RECIPIENT)
    (asserts! (> transfer-price u0) ERR-INVALID-AMOUNT)
    (ok (map-set policy-transfers
      { farmer: tx-sender }
      {
        recipient: recipient,
        transfer-price: transfer-price,
        confirmed: false
      }
    ))
  )
)

(define-public (confirm-policy-transfer (farmer principal))
  (let
    (
      (transfer (unwrap! (map-get? policy-transfers { farmer: farmer }) ERR-NO-POLICY))
      (policy (unwrap! (get-policy farmer) ERR-NO-POLICY))
      (current-block stacks-block-height)
    )
    (asserts! (is-eq tx-sender (get recipient transfer)) ERR-NOT-AUTHORIZED)
    (asserts! (not (get confirmed transfer)) ERR-POLICY-NOT-TRANSFERABLE)
    (asserts! (> (get end-block policy) current-block) ERR-POLICY-EXPIRED)
    (asserts! (is-none (get-policy tx-sender)) ERR-POLICY-EXISTS)
    (try! (stx-transfer? (get transfer-price transfer) tx-sender farmer))
    (map-delete policies { farmer: farmer })
    (map-set policies
      { farmer: tx-sender }
      policy
    )
    (map-set policy-transfers
      { farmer: farmer }
      (merge transfer { confirmed: true })
    )
    (ok true)
  )
)

(define-public (cancel-policy-transfer)
  (begin
    (asserts! (is-some (map-get? policy-transfers { farmer: tx-sender })) ERR-NO-POLICY)
    (map-delete policy-transfers { farmer: tx-sender })
    (ok true)
  )
)

(define-read-only (get-policy-transfer (farmer principal))
  (map-get? policy-transfers { farmer: farmer })
)

(define-public (enable-auto-renewal (max-premium uint))
  (begin
    (asserts! (> max-premium u0) ERR-INVALID-AMOUNT)
    (ok (map-set auto-renewals
      { farmer: tx-sender }
      {
        enabled: true,
        max-premium: max-premium,
        renewal-count: u0
      }
    ))
  )
)

(define-public (disable-auto-renewal)
  (begin
    (asserts! (is-some (map-get? auto-renewals { farmer: tx-sender })) ERR-RENEWAL-NOT-ENABLED)
    (map-delete auto-renewals { farmer: tx-sender })
    (ok true)
  )
)

(define-public (execute-auto-renewal (farmer principal))
  (let
    (
      (policy (unwrap! (get-policy farmer) ERR-NO-POLICY))
      (renewal-settings (unwrap! (map-get? auto-renewals { farmer: farmer }) ERR-RENEWAL-NOT-ENABLED))
      (current-block stacks-block-height)
      (new-premium (get premium policy))
      (new-coverage (* new-premium (var-get payout-multiplier)))
      (policy-duration u144)
    )
    (asserts! (get enabled renewal-settings) ERR-RENEWAL-NOT-ENABLED)
    (asserts! (not (get active policy)) ERR-POLICY-EXISTS)
    (asserts! (>= current-block (get end-block policy)) ERR-POLICY-EXPIRED)
    (asserts! (<= new-premium (get max-premium renewal-settings)) ERR-INSUFFICIENT-BALANCE-FOR-RENEWAL)
    (asserts! (>= (var-get total-pool-balance) new-coverage) ERR-INSUFFICIENT-POOL-BALANCE)
    (try! (as-contract (stx-transfer? new-premium farmer (as-contract tx-sender))))
    (var-set total-pool-balance (+ (var-get total-pool-balance) new-premium))
    (map-set policies
      { farmer: farmer }
      {
        premium: new-premium,
        coverage: new-coverage,
        rainfall-threshold: (get rainfall-threshold policy),
        active: true,
        start-block: current-block,
        end-block: (+ current-block policy-duration)
      }
    )
    (map-set auto-renewals
      { farmer: farmer }
      (merge renewal-settings { renewal-count: (+ (get renewal-count renewal-settings) u1) })
    )
    (ok true)
  )
)

(define-read-only (get-auto-renewal-settings (farmer principal))
  (map-get? auto-renewals { farmer: farmer })
)