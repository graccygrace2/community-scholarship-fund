;; Scholarship Pool Contract
;; Manage community contributions to educational scholarship funds

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-insufficient-funds (err u101))
(define-constant err-invalid-amount (err u102))
(define-constant err-pool-not-found (err u103))
(define-constant err-unauthorized (err u104))
(define-constant err-pool-inactive (err u105))

;; Data variables
(define-data-var total-pools uint u0)
(define-data-var total-contributions uint u0)
(define-data-var contract-balance uint u0)

;; Data maps
(define-map scholarship-pools 
  { pool-id: uint }
  {
    name: (string-ascii 50),
    description: (string-ascii 200),
    target-amount: uint,
    current-amount: uint,
    creator: principal,
    active: bool,
    created-at: uint
  }
)

(define-map pool-contributions
  { contributor: principal, pool-id: uint }
  { amount: uint, timestamp: uint }
)

(define-map contributor-stats
  { contributor: principal }
  { total-contributed: uint, pools-supported: uint, last-contribution: uint }
)

(define-map pool-contributors
  { pool-id: uint }
  { contributor-count: uint, total-raised: uint }
)

;; Public functions

;; Create a new scholarship pool
(define-public (create-pool (name (string-ascii 50)) (description (string-ascii 200)) (target-amount uint))
  (let 
    (
      (pool-id (+ (var-get total-pools) u1))
      (current-block-height block-height)
    )
    (asserts! (> target-amount u0) err-invalid-amount)
    (asserts! (> (len name) u0) err-invalid-amount)
    
    ;; Create the pool
    (map-set scholarship-pools
      { pool-id: pool-id }
      {
        name: name,
        description: description,
        target-amount: target-amount,
        current-amount: u0,
        creator: tx-sender,
        active: true,
        created-at: current-block-height
      }
    )
    
    ;; Initialize pool contributors
    (map-set pool-contributors
      { pool-id: pool-id }
      { contributor-count: u0, total-raised: u0 }
    )
    
    ;; Update total pools counter
    (var-set total-pools pool-id)
    
    (ok pool-id)
  )
)

;; Contribute to a scholarship pool
(define-public (contribute-to-pool (pool-id uint) (amount uint))
  (let 
    (
      (pool-info (unwrap! (map-get? scholarship-pools { pool-id: pool-id }) err-pool-not-found))
      (contributor-info (default-to 
        { total-contributed: u0, pools-supported: u0, last-contribution: u0 }
        (map-get? contributor-stats { contributor: tx-sender })
      ))
      (pool-stats (default-to
        { contributor-count: u0, total-raised: u0 }
        (map-get? pool-contributors { pool-id: pool-id })
      ))
      (existing-contribution (map-get? pool-contributions { contributor: tx-sender, pool-id: pool-id }))
      (is-new-contributor (is-none existing-contribution))
    )
    
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (get active pool-info) err-pool-inactive)
    (asserts! (>= (stx-get-balance tx-sender) amount) err-insufficient-funds)
    
    ;; Transfer STX to contract
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    ;; Update pool information
    (map-set scholarship-pools
      { pool-id: pool-id }
      (merge pool-info { current-amount: (+ (get current-amount pool-info) amount) })
    )
    
    ;; Update or create contribution record
    (map-set pool-contributions
      { contributor: tx-sender, pool-id: pool-id }
      {
        amount: (+ amount (match existing-contribution 
                           contribution (get amount contribution)
                           u0)),
        timestamp: block-height
      }
    )
    
    ;; Update contributor stats
    (map-set contributor-stats
      { contributor: tx-sender }
      {
        total-contributed: (+ (get total-contributed contributor-info) amount),
        pools-supported: (if is-new-contributor 
                          (+ (get pools-supported contributor-info) u1)
                          (get pools-supported contributor-info)),
        last-contribution: block-height
      }
    )
    
    ;; Update pool statistics
    (map-set pool-contributors
      { pool-id: pool-id }
      {
        contributor-count: (if is-new-contributor
                            (+ (get contributor-count pool-stats) u1)
                            (get contributor-count pool-stats)),
        total-raised: (+ (get total-raised pool-stats) amount)
      }
    )
    
    ;; Update global counters
    (var-set total-contributions (+ (var-get total-contributions) u1))
    (var-set contract-balance (+ (var-get contract-balance) amount))
    
    (ok amount)
  )
)

;; Withdraw funds from pool (only pool creator or contract owner)
(define-public (withdraw-from-pool (pool-id uint) (amount uint) (recipient principal))
  (let 
    (
      (pool-info (unwrap! (map-get? scholarship-pools { pool-id: pool-id }) err-pool-not-found))
    )
    
    (asserts! (or (is-eq tx-sender (get creator pool-info)) (is-eq tx-sender contract-owner)) err-unauthorized)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (>= (get current-amount pool-info) amount) err-insufficient-funds)
    
    ;; Transfer funds from contract to recipient
    (try! (as-contract (stx-transfer? amount tx-sender recipient)))
    
    ;; Update pool current amount
    (map-set scholarship-pools
      { pool-id: pool-id }
      (merge pool-info { current-amount: (- (get current-amount pool-info) amount) })
    )
    
    ;; Update contract balance
    (var-set contract-balance (- (var-get contract-balance) amount))
    
    (ok amount)
  )
)

;; Toggle pool active status (only creator or contract owner)
(define-public (toggle-pool-status (pool-id uint))
  (let 
    (
      (pool-info (unwrap! (map-get? scholarship-pools { pool-id: pool-id }) err-pool-not-found))
    )
    
    (asserts! (or (is-eq tx-sender (get creator pool-info)) (is-eq tx-sender contract-owner)) err-unauthorized)
    
    (map-set scholarship-pools
      { pool-id: pool-id }
      (merge pool-info { active: (not (get active pool-info)) })
    )
    
    (ok (not (get active pool-info)))
  )
)

;; Read-only functions

;; Get pool information
(define-read-only (get-pool-info (pool-id uint))
  (map-get? scholarship-pools { pool-id: pool-id })
)

;; Get contribution information
(define-read-only (get-contribution-info (contributor principal) (pool-id uint))
  (map-get? pool-contributions { contributor: contributor, pool-id: pool-id })
)

;; Get contributor statistics
(define-read-only (get-contributor-stats (contributor principal))
  (map-get? contributor-stats { contributor: contributor })
)

;; Get pool statistics
(define-read-only (get-pool-stats (pool-id uint))
  (map-get? pool-contributors { pool-id: pool-id })
)

;; Get total pools
(define-read-only (get-total-pools)
  (var-get total-pools)
)

;; Get total contributions count
(define-read-only (get-total-contributions)
  (var-get total-contributions)
)

;; Get contract balance
(define-read-only (get-contract-balance)
  (var-get contract-balance)
)

;; Get contract owner
(define-read-only (get-contract-owner)
  contract-owner
)

;; Check if pool is fully funded
(define-read-only (is-pool-fully-funded (pool-id uint))
  (match (map-get? scholarship-pools { pool-id: pool-id })
    pool-info (>= (get current-amount pool-info) (get target-amount pool-info))
    false
  )
)

;; Get pool funding percentage
(define-read-only (get-pool-funding-percentage (pool-id uint))
  (match (map-get? scholarship-pools { pool-id: pool-id })
    pool-info
      (if (> (get target-amount pool-info) u0)
        (/ (* (get current-amount pool-info) u100) (get target-amount pool-info))
        u0
      )
    u0
  )
)


;; title: scholarship-pool
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

