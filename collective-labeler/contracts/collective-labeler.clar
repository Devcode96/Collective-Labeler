;; CollectiveLabeler
;; Decentralized data annotation marketplace

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u300))
(define-constant err-not-found (err u301))
(define-constant err-already-submitted (err u302))
(define-constant err-insufficient-funds (err u303))
(define-constant err-not-authorized (err u304))
(define-constant err-task-closed (err u305))

;; Data Variables
(define-data-var task-id-nonce uint u0)
(define-data-var submission-id-nonce uint u0)

;; Data Maps
(define-map tasks
    uint
    {
        creator: principal,
        description: (string-ascii 500),
        reward-per-item: uint,
        total-items: uint,
        completed-items: uint,
        escrow-amount: uint,
        active: bool
    }
)

(define-map submissions
    uint
    {
        task-id: uint,
        labeler: principal,
        data-hash: (buff 32),
        verified: bool,
        paid: bool,
        timestamp: uint
    }
)

(define-map labeler-submissions
    {task-id: uint, labeler: principal}
    uint
)