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

;; Read-only functions
(define-read-only (get-task (task-id uint))
    (map-get? tasks task-id)
)

(define-read-only (get-submission (submission-id uint))
    (map-get? submissions submission-id)
)

(define-read-only (get-labeler-submission-count (task-id uint) (labeler principal))
    (default-to u0 (map-get? labeler-submissions {task-id: task-id, labeler: labeler}))
)

(define-read-only (get-next-task-id)
    (var-get task-id-nonce)
)

;; Public functions
;; #[allow(unchecked_data)]
(define-public (create-task (description (string-ascii 500)) (reward-per-item uint) (total-items uint))
    (let
        ((new-id (var-get task-id-nonce))
         (escrow-amount (* reward-per-item total-items)))
        (asserts! (> escrow-amount u0) err-insufficient-funds)
        (try! (stx-transfer? escrow-amount tx-sender (as-contract tx-sender)))
        (map-set tasks new-id
            {
                creator: tx-sender,
                description: description,
                reward-per-item: reward-per-item,
                total-items: total-items,
                completed-items: u0,
                escrow-amount: escrow-amount,
                active: true
            }
        )
        (var-set task-id-nonce (+ new-id u1))
        (ok new-id)
    )
)

;; #[allow(unchecked_data)]
(define-public (submit-annotation (task-id uint) (data-hash (buff 32)))
    (let
        ((task (unwrap! (map-get? tasks task-id) err-not-found))
         (new-submission-id (var-get submission-id-nonce)))
        (asserts! (get active task) err-task-closed)
        (asserts! (< (get completed-items task) (get total-items task)) err-task-closed)
        (map-set submissions new-submission-id
            {
                task-id: task-id,
                labeler: tx-sender,
                data-hash: data-hash,
                verified: false,
                paid: false,
                timestamp: stacks-block-height
            }
        )
        (map-set labeler-submissions 
            {task-id: task-id, labeler: tx-sender}
            (+ (get-labeler-submission-count task-id tx-sender) u1)
        )
        (var-set submission-id-nonce (+ new-submission-id u1))
        (ok new-submission-id)
    )
)

(define-public (verify-and-pay (submission-id uint))
    (let
        ((submission (unwrap! (map-get? submissions submission-id) err-not-found))
         (task (unwrap! (map-get? tasks (get task-id submission)) err-not-found)))
        (asserts! (is-eq tx-sender (get creator task)) err-not-authorized)
        (asserts! (not (get paid submission)) err-already-submitted)
        (try! (as-contract (stx-transfer? (get reward-per-item task) tx-sender (get labeler submission))))
        (map-set submissions submission-id 
            (merge submission {verified: true, paid: true}))
        (map-set tasks (get task-id submission)
            (merge task {completed-items: (+ (get completed-items task) u1)}))
        (ok true)
    )
)

(define-public (close-task (task-id uint))
    (let
        ((task (unwrap! (map-get? tasks task-id) err-not-found))
         (remaining (* (get reward-per-item task) (- (get total-items task) (get completed-items task)))))
        (asserts! (is-eq tx-sender (get creator task)) err-not-authorized)
        (if (> remaining u0)
            (try! (as-contract (stx-transfer? remaining tx-sender (get creator task))))
            true
        )
        (map-set tasks task-id (merge task {active: false}))
        (ok true)
    )
)