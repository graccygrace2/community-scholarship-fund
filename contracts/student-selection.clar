;; Student Selection Contract
;; Fair selection process for scholarship recipients based on need and merit

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u200))
(define-constant err-not-found (err u201))
(define-constant err-unauthorized (err u202))
(define-constant err-invalid-data (err u203))
(define-constant err-already-exists (err u204))
(define-constant err-voting-closed (err u205))
(define-constant err-already-voted (err u206))
(define-constant err-invalid-score (err u207))
(define-constant err-selection-active (err u208))

;; Data variables
(define-data-var total-applications uint u0)
(define-data-var total-selections uint u0)
(define-data-var voting-period uint u1000) ;; blocks

;; Data maps
(define-map student-applications
  { application-id: uint }
  {
    student: principal,
    name: (string-ascii 100),
    academic-info: (string-ascii 200),
    financial-need-score: uint, ;; 1-100
    merit-score: uint, ;; 1-100
    total-score: uint,
    pool-id: uint,
    status: (string-ascii 20), ;; "pending", "approved", "rejected"
    created-at: uint,
    updated-at: uint
  }
)

(define-map selection-rounds
  { selection-id: uint }
  {
    pool-id: uint,
    voting-start: uint,
    voting-end: uint,
    total-votes: uint,
    status: (string-ascii 20), ;; "active", "voting", "completed"
    winner: (optional uint),
    created-at: uint
  }
)

(define-map community-votes
  { voter: principal, selection-id: uint, application-id: uint }
  { vote-weight: uint, timestamp: uint }
)

(define-map application-votes
  { application-id: uint, selection-id: uint }
  { total-votes: uint, vote-count: uint }
)

(define-map voter-stats
  { voter: principal }
  { total-votes: uint, selections-participated: uint, last-vote: uint }
)

(define-map student-history
  { student: principal }
  { applications-submitted: uint, scholarships-won: uint, last-application: uint }
)

;; Public functions

;; Submit student application
(define-public (submit-application 
    (name (string-ascii 100))
    (academic-info (string-ascii 200))
    (financial-need-score uint)
    (merit-score uint)
    (pool-id uint)
  )
  (let 
    (
      (application-id (+ (var-get total-applications) u1))
      (current-block block-height)
      (total-score (+ financial-need-score merit-score))
      (student-info (default-to
        { applications-submitted: u0, scholarships-won: u0, last-application: u0 }
        (map-get? student-history { student: tx-sender })
      ))
    )
    
    (asserts! (> (len name) u0) err-invalid-data)
    (asserts! (and (>= financial-need-score u1) (<= financial-need-score u100)) err-invalid-score)
    (asserts! (and (>= merit-score u1) (<= merit-score u100)) err-invalid-score)
    (asserts! (> pool-id u0) err-invalid-data)
    
    ;; Create application record
    (map-set student-applications
      { application-id: application-id }
      {
        student: tx-sender,
        name: name,
        academic-info: academic-info,
        financial-need-score: financial-need-score,
        merit-score: merit-score,
        total-score: total-score,
        pool-id: pool-id,
        status: "pending",
        created-at: current-block,
        updated-at: current-block
      }
    )
    
    ;; Update student history
    (map-set student-history
      { student: tx-sender }
      {
        applications-submitted: (+ (get applications-submitted student-info) u1),
        scholarships-won: (get scholarships-won student-info),
        last-application: current-block
      }
    )
    
    ;; Update total applications counter
    (var-set total-applications application-id)
    
    (ok application-id)
  )
)

;; Create selection round (simplified)
(define-public (create-selection-round (pool-id uint))
  (let 
    (
      (selection-id (+ (var-get total-selections) u1))
      (current-block block-height)
      (voting-end (+ current-block (var-get voting-period)))
    )
    
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> pool-id u0) err-invalid-data)
    
    ;; Create selection round
    (map-set selection-rounds
      { selection-id: selection-id }
      {
        pool-id: pool-id,
        voting-start: current-block,
        voting-end: voting-end,
        total-votes: u0,
        status: "voting",
        winner: none,
        created-at: current-block
      }
    )
    
    ;; Update total selections counter
    (var-set total-selections selection-id)
    
    (ok selection-id)
  )
)

;; Vote for student in selection round
(define-public (vote-for-student (selection-id uint) (application-id uint) (vote-weight uint))
  (let 
    (
      (selection-info (unwrap! (map-get? selection-rounds { selection-id: selection-id }) err-not-found))
      (current-block block-height)
      (existing-vote (map-get? community-votes 
        { voter: tx-sender, selection-id: selection-id, application-id: application-id }))
      (voter-info (default-to
        { total-votes: u0, selections-participated: u0, last-vote: u0 }
        (map-get? voter-stats { voter: tx-sender })
      ))
      (app-votes (default-to
        { total-votes: u0, vote-count: u0 }
        (map-get? application-votes { application-id: application-id, selection-id: selection-id })
      ))
    )
    
    (asserts! (is-eq (get status selection-info) "voting") err-voting-closed)
    (asserts! (<= current-block (get voting-end selection-info)) err-voting-closed)
    (asserts! (is-none existing-vote) err-already-voted)
    (asserts! (and (>= vote-weight u1) (<= vote-weight u10)) err-invalid-score)
    
    ;; Record the vote
    (map-set community-votes
      { voter: tx-sender, selection-id: selection-id, application-id: application-id }
      { vote-weight: vote-weight, timestamp: current-block }
    )
    
    ;; Update application vote totals
    (map-set application-votes
      { application-id: application-id, selection-id: selection-id }
      {
        total-votes: (+ (get total-votes app-votes) vote-weight),
        vote-count: (+ (get vote-count app-votes) u1)
      }
    )
    
    ;; Update voter statistics
    (map-set voter-stats
      { voter: tx-sender }
      {
        total-votes: (+ (get total-votes voter-info) u1),
        selections-participated: (if (is-eq (get last-vote voter-info) u0)
                                  (+ (get selections-participated voter-info) u1)
                                  (get selections-participated voter-info)),
        last-vote: current-block
      }
    )
    
    ;; Update selection round total votes
    (map-set selection-rounds
      { selection-id: selection-id }
      (merge selection-info { total-votes: (+ (get total-votes selection-info) u1) })
    )
    
    (ok vote-weight)
  )
)

;; Approve application (simplified)
(define-public (approve-application (application-id uint))
  (let 
    (
      (app-info (unwrap! (map-get? student-applications { application-id: application-id }) err-not-found))
      (student-info (default-to
        { applications-submitted: u0, scholarships-won: u0, last-application: u0 }
        (map-get? student-history { student: (get student app-info) })
      ))
    )
    
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (is-eq (get status app-info) "pending") err-invalid-data)
    
    ;; Update application status
    (map-set student-applications
      { application-id: application-id }
      (merge app-info {
        status: "approved",
        updated-at: block-height
      })
    )
    
    ;; Update student history
    (map-set student-history
      { student: (get student app-info) }
      (merge student-info { scholarships-won: (+ (get scholarships-won student-info) u1) })
    )
    
    (ok application-id)
  )
)

;; Reject application
(define-public (reject-application (application-id uint))
  (let 
    (
      (app-info (unwrap! (map-get? student-applications { application-id: application-id }) err-not-found))
    )
    
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (is-eq (get status app-info) "pending") err-invalid-data)
    
    ;; Update application status
    (map-set student-applications
      { application-id: application-id }
      (merge app-info {
        status: "rejected",
        updated-at: block-height
      })
    )
    
    (ok application-id)
  )
)

;; Read-only functions

;; Get application information
(define-read-only (get-application (application-id uint))
  (map-get? student-applications { application-id: application-id })
)

;; Get selection round information
(define-read-only (get-selection-round (selection-id uint))
  (map-get? selection-rounds { selection-id: selection-id })
)

;; Get vote information
(define-read-only (get-vote-info (voter principal) (selection-id uint) (application-id uint))
  (map-get? community-votes { voter: voter, selection-id: selection-id, application-id: application-id })
)

;; Get application vote totals
(define-read-only (get-application-votes (application-id uint) (selection-id uint))
  (map-get? application-votes { application-id: application-id, selection-id: selection-id })
)

;; Get voter statistics
(define-read-only (get-voter-stats (voter principal))
  (map-get? voter-stats { voter: voter })
)

;; Get student history
(define-read-only (get-student-history (student principal))
  (map-get? student-history { student: student })
)

;; Get total applications
(define-read-only (get-total-applications)
  (var-get total-applications)
)

;; Get total selections
(define-read-only (get-total-selections)
  (var-get total-selections)
)

;; Get voting period
(define-read-only (get-voting-period)
  (var-get voting-period)
)

;; Check if voting is active
(define-read-only (is-voting-active (selection-id uint))
  (match (map-get? selection-rounds { selection-id: selection-id })
    selection-info
      (and 
        (is-eq (get status selection-info) "voting")
        (<= block-height (get voting-end selection-info))
      )
    false
  )
)

;; Get applications by status
(define-read-only (get-application-status (application-id uint))
  (match (map-get? student-applications { application-id: application-id })
    app-info (get status app-info)
    "not-found"
  )
)

;; Get applications by pool
(define-read-only (get-application-pool (application-id uint))
  (match (map-get? student-applications { application-id: application-id })
    app-info (get pool-id app-info)
    u0
  )
)


;; title: student-selection
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

