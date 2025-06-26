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

(define-constant COLLATERAL_RATIO u150)
(define-constant INTEREST_RATE u5)
(define-constant LOAN_DURATION u144)
(define-constant LIQUIDATION_PENALTY u10)

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
