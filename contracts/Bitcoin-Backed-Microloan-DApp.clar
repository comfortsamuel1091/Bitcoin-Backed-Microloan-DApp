(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_LOAN_NOT_FOUND (err u101))
(define-constant ERR_INSUFFICIENT_COLLATERAL (err u102))
(define-constant ERR_LOAN_ALREADY_EXISTS (err u103))
(define-constant ERR_LOAN_EXPIRED (err u104))
(define-constant ERR_LOAN_NOT_EXPIRED (err u105))
(define-constant ERR_INSUFFICIENT_BALANCE (err u106))
(define-constant ERR_INVALID_AMOUNT (err u107))
(define-constant ERR_LOAN_ALREADY_REPAID (err u108))

(define-constant ERR_EXTENSION_NOT_ALLOWED (err u109))
(define-constant ERR_LOAN_TOO_CLOSE_TO_EXPIRY (err u110))
(define-constant ERR_MAX_EXTENSIONS_REACHED (err u111))

(define-constant EXTENSION_FEE_RATE u3)
(define-constant EXTENSION_DURATION u72)
(define-constant MAX_EXTENSIONS u2)
(define-constant MIN_BLOCKS_BEFORE_EXTENSION u12)

(define-constant COLLATERAL_RATIO u150)
(define-constant INTEREST_RATE u5)
(define-constant LOAN_DURATION u144)
(define-constant LIQUIDATION_PENALTY u10)

(define-constant MIN_INTEREST_RATE u2)
(define-constant MAX_INTEREST_RATE u15)
(define-constant TARGET_UTILIZATION u70)
(define-constant RATE_ADJUSTMENT_FACTOR u10)

(define-data-var current-interest-rate uint u5)
(define-data-var last-rate-update uint u0)
(define-data-var rate-update-frequency uint u72)

(define-fungible-token microloan-token)

(define-map loans
  { borrower: principal }
  {
    collateral-amount: uint,
    loan-amount: uint,
    interest-amount: uint,
    start-block: uint,
    end-block: uint,
    is-active: bool,
    is-repaid: bool
  }
)

(define-map user-balances
  { user: principal }
  { balance: uint }
)

(define-data-var total-supply uint u1000000)
(define-data-var btc-price uint u50000)
(define-data-var total-loans-issued uint u0)
(define-data-var total-collateral-locked uint u0)

(define-private (calculate-interest (amount uint))
  (/ (* amount INTEREST_RATE) u100)
)

(define-private (calculate-loan-amount (collateral uint))
  (let ((btc-value (* collateral (var-get btc-price))))
    (/ (* btc-value u100) COLLATERAL_RATIO))
)

(define-private (is-loan-expired (end-block uint))
  (> stacks-block-height end-block)
)

(define-private (get-current-block)
  stacks-block-height
)

(define-public (initialize-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (try! (ft-mint? microloan-token (var-get total-supply) CONTRACT_OWNER))
    (map-set user-balances { user: CONTRACT_OWNER } { balance: (var-get total-supply) })
    (ok true)
  )
)

(define-public (update-btc-price (new-price uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> new-price u0) ERR_INVALID_AMOUNT)
    (var-set btc-price new-price)
    (ok true)
  )
)

(define-public (request-loan (collateral-amount uint))
  (let (
    (borrower tx-sender)
    (current-block (get-current-block))
    (loan-amount (calculate-loan-amount collateral-amount))
    (interest (calculate-interest loan-amount))
    (end-block (+ current-block LOAN_DURATION))
    (existing-loan (map-get? loans { borrower: borrower }))
  )
    (asserts! (> collateral-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (is-none existing-loan) ERR_LOAN_ALREADY_EXISTS)
    (asserts! (>= (stx-get-balance borrower) collateral-amount) ERR_INSUFFICIENT_BALANCE)
    
    (try! (stx-transfer? collateral-amount borrower (as-contract tx-sender)))
    (try! (as-contract (ft-transfer? microloan-token loan-amount tx-sender borrower)))
    
    (map-set loans
      { borrower: borrower }
      {
        collateral-amount: collateral-amount,
        loan-amount: loan-amount,
        interest-amount: interest,
        start-block: current-block,
        end-block: end-block,
        is-active: true,
        is-repaid: false
      }
    )
    
    (var-set total-loans-issued (+ (var-get total-loans-issued) u1))
    (var-set total-collateral-locked (+ (var-get total-collateral-locked) collateral-amount))
    
    (ok { loan-amount: loan-amount, interest: interest, end-block: end-block })
  )
)

(define-public (repay-loan)
  (let (
    (borrower tx-sender)
    (loan-data (unwrap! (map-get? loans { borrower: borrower }) ERR_LOAN_NOT_FOUND))
    (total-repayment (+ (get loan-amount loan-data) (get interest-amount loan-data)))
  )
    (asserts! (get is-active loan-data) ERR_LOAN_NOT_FOUND)
    (asserts! (not (get is-repaid loan-data)) ERR_LOAN_ALREADY_REPAID)
    (asserts! (not (is-loan-expired (get end-block loan-data))) ERR_LOAN_EXPIRED)
    (asserts! (>= (ft-get-balance microloan-token borrower) total-repayment) ERR_INSUFFICIENT_BALANCE)
    
    (try! (ft-transfer? microloan-token total-repayment borrower (as-contract tx-sender)))
    (try! (as-contract (stx-transfer? (get collateral-amount loan-data) tx-sender borrower)))
    
    (map-set loans
      { borrower: borrower }
      (merge loan-data { is-active: false, is-repaid: true })
    )
    
    (var-set total-collateral-locked (- (var-get total-collateral-locked) (get collateral-amount loan-data)))
    
    (ok true)
  )
)

(define-public (liquidate-loan (borrower principal))
  (let (
    (loan-data (unwrap! (map-get? loans { borrower: borrower }) ERR_LOAN_NOT_FOUND))
    (penalty-amount (/ (* (get collateral-amount loan-data) LIQUIDATION_PENALTY) u100))
    (remaining-collateral (- (get collateral-amount loan-data) penalty-amount))
  )
    (asserts! (get is-active loan-data) ERR_LOAN_NOT_FOUND)
    (asserts! (not (get is-repaid loan-data)) ERR_LOAN_ALREADY_REPAID)
    (asserts! (is-loan-expired (get end-block loan-data)) ERR_LOAN_NOT_EXPIRED)
    
    (try! (as-contract (stx-transfer? penalty-amount tx-sender CONTRACT_OWNER)))
    (try! (as-contract (stx-transfer? remaining-collateral tx-sender borrower)))
    
    (map-set loans
      { borrower: borrower }
      (merge loan-data { is-active: false })
    )
    
    (var-set total-collateral-locked (- (var-get total-collateral-locked) (get collateral-amount loan-data)))
    
    (ok true)
  )
)

(define-public (transfer-tokens (amount uint) (recipient principal))
  (begin
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (ft-transfer? microloan-token amount tx-sender recipient)
  )
)

(define-read-only (get-loan-info (borrower principal))
  (map-get? loans { borrower: borrower })
)

(define-read-only (get-user-balance (user principal))
  (ft-get-balance microloan-token user)
)

(define-read-only (get-btc-price)
  (var-get btc-price)
)

(define-read-only (get-contract-stats)
  {
    total-loans: (var-get total-loans-issued),
    total-collateral: (var-get total-collateral-locked),
    btc-price: (var-get btc-price),
    contract-balance: (stx-get-balance (as-contract tx-sender))
  }
)

(define-read-only (calculate-max-loan (collateral uint))
  (calculate-loan-amount collateral)
)

(define-read-only (get-loan-status (borrower principal))
  (match (map-get? loans { borrower: borrower })
    loan-data
    {
      is-active: (get is-active loan-data),
      is-expired: (is-loan-expired (get end-block loan-data)),
      blocks-remaining: (if (> (get end-block loan-data) stacks-block-height)
                          (- (get end-block loan-data) stacks-block-height)
                          u0),
      total-due: (+ (get loan-amount loan-data) (get interest-amount loan-data))
    }
    { is-active: false, is-expired: false, blocks-remaining: u0, total-due: u0 }
  )
)

(define-public (emergency-withdraw)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (try! (as-contract (stx-transfer? (stx-get-balance tx-sender) tx-sender CONTRACT_OWNER)))
    (ok true)
  )
)



(define-map loan-extensions
  { borrower: principal }
  { extensions-used: uint }
)

(define-private (calculate-extension-fee (loan-amount uint))
  (/ (* loan-amount EXTENSION_FEE_RATE) u100)
)

(define-private (can-extend-loan (loan-data (tuple (collateral-amount uint) (loan-amount uint) (interest-amount uint) (start-block uint) (end-block uint) (is-active bool) (is-repaid bool))) (borrower principal))
  (let (
    (extensions-data (default-to { extensions-used: u0 } (map-get? loan-extensions { borrower: borrower })))
    (blocks-until-expiry (- (get end-block loan-data) stacks-block-height))
  )
    (and
      (get is-active loan-data)
      (not (get is-repaid loan-data))
      (< (get extensions-used extensions-data) MAX_EXTENSIONS)
      (> blocks-until-expiry MIN_BLOCKS_BEFORE_EXTENSION)
      (not (is-loan-expired (get end-block loan-data)))
    )
  )
)

(define-public (extend-loan)
  (let (
    (borrower tx-sender)
    (loan-data (unwrap! (map-get? loans { borrower: borrower }) ERR_LOAN_NOT_FOUND))
    (extensions-data (default-to { extensions-used: u0 } (map-get? loan-extensions { borrower: borrower })))
    (extension-fee (calculate-extension-fee (get loan-amount loan-data)))
    (new-end-block (+ (get end-block loan-data) EXTENSION_DURATION))
  )
    (asserts! (can-extend-loan loan-data borrower) ERR_EXTENSION_NOT_ALLOWED)
    (asserts! (>= (ft-get-balance microloan-token borrower) extension-fee) ERR_INSUFFICIENT_BALANCE)
    
    (try! (ft-transfer? microloan-token extension-fee borrower (as-contract tx-sender)))
    
    (map-set loans
      { borrower: borrower }
      (merge loan-data { end-block: new-end-block })
    )
    
    (map-set loan-extensions
      { borrower: borrower }
      { extensions-used: (+ (get extensions-used extensions-data) u1) }
    )
    
    (ok { new-end-block: new-end-block, fee-paid: extension-fee })
  )
)

(define-read-only (get-extension-info (borrower principal))
  (let (
    (loan-data (map-get? loans { borrower: borrower }))
    (extensions-data (default-to { extensions-used: u0 } (map-get? loan-extensions { borrower: borrower })))
  )
    (match loan-data
      loan
      {
        can-extend: (can-extend-loan loan borrower),
        extensions-used: (get extensions-used extensions-data),
        max-extensions: MAX_EXTENSIONS,
        extension-fee: (calculate-extension-fee (get loan-amount loan))
      }
      { can-extend: false, extensions-used: u0, max-extensions: MAX_EXTENSIONS, extension-fee: u0 }
    )
  )
)


(define-private (calculate-utilization-rate)
  (let (
    (total-stx-locked (var-get total-collateral-locked))
    (contract-balance (stx-get-balance (as-contract tx-sender)))
    (total-liquidity (+ total-stx-locked contract-balance))
  )
    (if (> total-liquidity u0)
        (/ (* total-stx-locked u100) total-liquidity)
        u0)
  )
)

(define-private (calculate-new-interest-rate (utilization uint))
  (let (
    (rate-difference (if (> utilization TARGET_UTILIZATION)
                        (/ (* (- utilization TARGET_UTILIZATION) RATE_ADJUSTMENT_FACTOR) u100)
                        (/ (* (- TARGET_UTILIZATION utilization) RATE_ADJUSTMENT_FACTOR) u100)))
    (base-rate (var-get current-interest-rate))
    (new-rate (if (> utilization TARGET_UTILIZATION)
                 (+ base-rate rate-difference)
                 (if (> base-rate rate-difference)
                     (- base-rate rate-difference)
                     MIN_INTEREST_RATE)))
  )
    (if (> new-rate MAX_INTEREST_RATE)
        MAX_INTEREST_RATE
        (if (< new-rate MIN_INTEREST_RATE)
            MIN_INTEREST_RATE
            new-rate))
  )
)

(define-private (should-update-rate)
  (>= (- stacks-block-height (var-get last-rate-update)) (var-get rate-update-frequency))
)

(define-public (update-interest-rate)
  (begin
    (asserts! (should-update-rate) (err u200))
    (let (
      (current-utilization (calculate-utilization-rate))
      (new-rate (calculate-new-interest-rate current-utilization))
    )
      (var-set current-interest-rate new-rate)
      (var-set last-rate-update stacks-block-height)
      (ok { new-rate: new-rate, utilization: current-utilization })
    )
  )
)

(define-private (get-dynamic-interest (amount uint))
  (/ (* amount (var-get current-interest-rate)) u100)
)

(define-read-only (get-current-rate-info)
  {
    current-rate: (var-get current-interest-rate),
    utilization: (calculate-utilization-rate),
    last-update: (var-get last-rate-update),
    can-update: (should-update-rate)
  }
)

(define-map borrower-performance
  { borrower: principal }
  {
    total-loans: uint,
    successful-repayments: uint,
    total-defaults: uint,
    avg-repayment-speed: uint,
    credit-score: uint,
    last-updated: uint
  }
)

(define-constant PERFECT_CREDIT_SCORE u850)
(define-constant MIN_CREDIT_SCORE u300)
(define-constant SPEED_BONUS_THRESHOLD u50)

(define-private (calculate-credit-score (performance-data (tuple (total-loans uint) (successful-repayments uint) (total-defaults uint) (avg-repayment-speed uint) (credit-score uint) (last-updated uint))))
  (let (
    (repayment-rate (if (> (get total-loans performance-data) u0)
                       (/ (* (get successful-repayments performance-data) u100) (get total-loans performance-data))
                       u100))
    (speed-bonus (if (<= (get avg-repayment-speed performance-data) SPEED_BONUS_THRESHOLD) u50 u0))
    (default-penalty (* (get total-defaults performance-data) u30))
    (base-score (+ (* repayment-rate u7) speed-bonus))
    (final-score (if (> base-score default-penalty)
                    (- base-score default-penalty)
                    MIN_CREDIT_SCORE))
  )
    (if (> final-score PERFECT_CREDIT_SCORE)
        PERFECT_CREDIT_SCORE
        (if (< final-score MIN_CREDIT_SCORE)
            MIN_CREDIT_SCORE
            final-score))
  )
)

(define-private (update-performance-on-repay (borrower principal) (loan-data (tuple (collateral-amount uint) (loan-amount uint) (interest-amount uint) (start-block uint) (end-block uint) (is-active bool) (is-repaid bool))))
  (let (
    (current-performance (default-to { total-loans: u0, successful-repayments: u0, total-defaults: u0, avg-repayment-speed: u0, credit-score: u750, last-updated: u0 } (map-get? borrower-performance { borrower: borrower })))
    (repayment-speed (- (get end-block loan-data) stacks-block-height))
    (new-avg-speed (if (> (get successful-repayments current-performance) u0)
                      (/ (+ (* (get avg-repayment-speed current-performance) (get successful-repayments current-performance)) repayment-speed)
                         (+ (get successful-repayments current-performance) u1))
                      repayment-speed))
    (updated-performance (merge current-performance {
      successful-repayments: (+ (get successful-repayments current-performance) u1),
      avg-repayment-speed: new-avg-speed,
      last-updated: stacks-block-height
    }))
    (new-credit-score (calculate-credit-score updated-performance))
  )
    (map-set borrower-performance
      { borrower: borrower }
      (merge updated-performance { credit-score: new-credit-score })
    )
  )
)

(define-private (update-performance-on-default (borrower principal))
  (let (
    (current-performance (default-to { total-loans: u0, successful-repayments: u0, total-defaults: u0, avg-repayment-speed: u0, credit-score: u750, last-updated: u0 } (map-get? borrower-performance { borrower: borrower })))
    (updated-performance (merge current-performance {
      total-defaults: (+ (get total-defaults current-performance) u1),
      last-updated: stacks-block-height
    }))
    (new-credit-score (calculate-credit-score updated-performance))
  )
    (map-set borrower-performance
      { borrower: borrower }
      (merge updated-performance { credit-score: new-credit-score })
    )
  )
)

(define-private (update-performance-on-loan-start (borrower principal))
  (let (
    (current-performance (default-to { total-loans: u0, successful-repayments: u0, total-defaults: u0, avg-repayment-speed: u0, credit-score: u750, last-updated: u0 } (map-get? borrower-performance { borrower: borrower })))
  )
    (map-set borrower-performance
      { borrower: borrower }
      (merge current-performance {
        total-loans: (+ (get total-loans current-performance) u1),
        last-updated: stacks-block-height
      })
    )
  )
)

(define-read-only (get-borrower-performance (borrower principal))
  (default-to { total-loans: u0, successful-repayments: u0, total-defaults: u0, avg-repayment-speed: u0, credit-score: u750, last-updated: u0 }
              (map-get? borrower-performance { borrower: borrower }))
)

(define-read-only (get-system-analytics)
  { 
    total-loans-issued: (var-get total-loans-issued),
    total-collateral-locked: (var-get total-collateral-locked),
    current-utilization: (calculate-utilization-rate),
    current-interest-rate: (var-get current-interest-rate)
  }
)