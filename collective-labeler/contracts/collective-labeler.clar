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

;; Additional Data Variables
(define-data-var platform-fee-percentage uint u2) ;; 2% platform fee
(define-data-var min-reward-per-item uint u10000) ;; Minimum 0.01 STX
(define-data-var total-tasks-completed uint u0)
(define-data-var total-platform-fees uint u0)

;; Additional Data Maps
(define-map labeler-stats
    principal
    {
        total-submissions: uint,
        verified-submissions: uint,
        total-earned: uint,
        tasks-participated: uint
    }
)

(define-map task-reviews
    {task-id: uint, labeler: principal}
    {
        rating: uint,
        comment: (string-ascii 200)
    }
)

(define-map labeler-reputation
    principal
    uint
)

(define-map task-categories
    uint
    (string-ascii 50)
)

;; Function 1: Get labeler statistics
(define-read-only (get-labeler-stats (labeler principal))
    (ok (default-to 
        {total-submissions: u0, verified-submissions: u0, total-earned: u0, tasks-participated: u0}
        (map-get? labeler-stats labeler)))
)

;; Function 2: Get labeler reputation score
(define-read-only (get-labeler-reputation (labeler principal))
    (ok (default-to u0 (map-get? labeler-reputation labeler)))
)

;; Function 3: Calculate task completion percentage
(define-read-only (get-task-completion-rate (task-id uint))
    (let
        ((task (unwrap! (map-get? tasks task-id) err-not-found)))
        (ok (if (> (get total-items task) u0)
            (/ (* (get completed-items task) u100) (get total-items task))
            u0
        ))
    )
)

;; Function 4: Get task remaining items
(define-read-only (get-remaining-items (task-id uint))
    (let
        ((task (unwrap! (map-get? tasks task-id) err-not-found)))
        (ok (- (get total-items task) (get completed-items task)))
    )
)

;; Function 5: Get platform statistics
(define-read-only (get-platform-stats)
    (ok {
        total-tasks: (var-get task-id-nonce),
        total-submissions: (var-get submission-id-nonce),
        completed-tasks: (var-get total-tasks-completed),
        platform-fees-collected: (var-get total-platform-fees)
    })
)

;; Function 6: Set minimum reward (owner only)
;; #[allow(unchecked_data)]
(define-public (set-min-reward (new-min uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set min-reward-per-item new-min)
        (ok true)
    )
)

;; Function 7: Set platform fee (owner only)
(define-public (set-platform-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= new-fee u10) err-not-authorized) ;; Max 10% fee
        (var-set platform-fee-percentage new-fee)
        (ok true)
    )
)

;; Function 8: Calculate platform fee for task
(define-read-only (calculate-platform-fee (reward-amount uint))
    (ok (/ (* reward-amount (var-get platform-fee-percentage)) u100))
)

;; Function 9: Enhanced task creation with fee
;; #[allow(unchecked_data)]
(define-public (create-task-v2 (description (string-ascii 500)) (reward-per-item uint) (total-items uint) (category (string-ascii 50)))
    (let
        ((new-id (var-get task-id-nonce))
         (escrow-amount (* reward-per-item total-items))
         (platform-fee (/ (* escrow-amount (var-get platform-fee-percentage)) u100))
         (total-cost (+ escrow-amount platform-fee)))
        (asserts! (>= reward-per-item (var-get min-reward-per-item)) err-insufficient-funds)
        (asserts! (> total-items u0) err-insufficient-funds)
        (try! (stx-transfer? total-cost tx-sender (as-contract tx-sender)))
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
        (map-set task-categories new-id category)
        (var-set total-platform-fees (+ (var-get total-platform-fees) platform-fee))
        (var-set task-id-nonce (+ new-id u1))
        (ok new-id)
    )
)

;; Function 10: Submit review for task
;; #[allow(unchecked_data)]
(define-public (submit-task-review (task-id uint) (rating uint) (comment (string-ascii 200)))
    (let
        ((task (unwrap! (map-get? tasks task-id) err-not-found))
         (submission-count (get-labeler-submission-count task-id tx-sender)))
        (asserts! (> submission-count u0) err-not-authorized)
        (asserts! (<= rating u5) err-not-authorized) ;; Max 5 stars
        (map-set task-reviews 
            {task-id: task-id, labeler: tx-sender}
            {rating: rating, comment: comment})
        (ok true)
    )
)

;; Function 11: Get task review
(define-read-only (get-task-review (task-id uint) (labeler principal))
    (ok (map-get? task-reviews {task-id: task-id, labeler: labeler}))
)

;; Function 12: Update labeler stats after verification
(define-private (update-labeler-stats (labeler principal) (reward uint))
    (let
        ((current-stats (default-to 
            {total-submissions: u0, verified-submissions: u0, total-earned: u0, tasks-participated: u0}
            (map-get? labeler-stats labeler))))
        (map-set labeler-stats labeler
            {
                total-submissions: (get total-submissions current-stats),
                verified-submissions: (+ (get verified-submissions current-stats) u1),
                total-earned: (+ (get total-earned current-stats) reward),
                tasks-participated: (get tasks-participated current-stats)
            })
        true
    )
)

;; Function 13: Enhanced submission with stats tracking
;; #[allow(unchecked_data)]
(define-public (submit-annotation-v2 (task-id uint) (data-hash (buff 32)))
    (let
        ((task (unwrap! (map-get? tasks task-id) err-not-found))
         (new-submission-id (var-get submission-id-nonce))
         (current-stats (default-to 
            {total-submissions: u0, verified-submissions: u0, total-earned: u0, tasks-participated: u0}
            (map-get? labeler-stats tx-sender)))
         (is-first-submission (is-eq (get-labeler-submission-count task-id tx-sender) u0)))
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
        (map-set labeler-stats tx-sender
            {
                total-submissions: (+ (get total-submissions current-stats) u1),
                verified-submissions: (get verified-submissions current-stats),
                total-earned: (get total-earned current-stats),
                tasks-participated: (if is-first-submission 
                    (+ (get tasks-participated current-stats) u1)
                    (get tasks-participated current-stats))
            })
        (var-set submission-id-nonce (+ new-submission-id u1))
        (ok new-submission-id)
    )
)

;; Function 14: Enhanced payment with stats update
(define-public (verify-and-pay-v2 (submission-id uint))
    (let
        ((submission (unwrap! (map-get? submissions submission-id) err-not-found))
         (task (unwrap! (map-get? tasks (get task-id submission)) err-not-found))
         (is-task-completed (is-eq (+ (get completed-items task) u1) (get total-items task))))
        (asserts! (is-eq tx-sender (get creator task)) err-not-authorized)
        (asserts! (not (get paid submission)) err-already-submitted)
        (try! (as-contract (stx-transfer? (get reward-per-item task) tx-sender (get labeler submission))))
        (map-set submissions submission-id 
            (merge submission {verified: true, paid: true}))
        (map-set tasks (get task-id submission)
            (merge task {
                completed-items: (+ (get completed-items task) u1),
                active: (not is-task-completed)
            }))
        (update-labeler-stats (get labeler submission) (get reward-per-item task))
        (if is-task-completed
            (var-set total-tasks-completed (+ (var-get total-tasks-completed) u1))
            true)
        (ok true)
    )
)

;; Function 15: Batch verify multiple submissions
(define-public (batch-verify-submissions (submission-ids (list 10 uint)))
    (ok (map verify-single-submission submission-ids))
)

;; Helper for batch verification
(define-private (verify-single-submission (submission-id uint))
    (match (verify-and-pay-v2 submission-id)
        success true
        error false
    )
)

;; Function 16: Get task category
(define-read-only (get-task-category (task-id uint))
    (ok (map-get? task-categories task-id))
)

;; Function 17: Check if task is complete
(define-read-only (is-task-complete (task-id uint))
    (let
        ((task (unwrap! (map-get? tasks task-id) err-not-found)))
        (ok (is-eq (get completed-items task) (get total-items task)))
    )
)

;; Function 18: Get labeler success rate
(define-read-only (get-labeler-success-rate (labeler principal))
    (let
        ((stats (default-to 
            {total-submissions: u0, verified-submissions: u0, total-earned: u0, tasks-participated: u0}
            (map-get? labeler-stats labeler))))
        (ok (if (> (get total-submissions stats) u0)
            (/ (* (get verified-submissions stats) u100) (get total-submissions stats))
            u0
        ))
    )
)

;; Function 19: Get all submissions for a task by labeler
(define-read-only (get-task-labeler-info (task-id uint) (labeler principal))
    (let
        ((task (unwrap! (map-get? tasks task-id) err-not-found))
         (submission-count (get-labeler-submission-count task-id labeler)))
        (ok {
            task-active: (get active task),
            submissions: submission-count,
            potential-earnings: (* submission-count (get reward-per-item task))
        })
    )
)

;; Function 20: Withdraw platform fees (owner only)
(define-public (withdraw-platform-fees (amount uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= amount (var-get total-platform-fees)) err-insufficient-funds)
        (try! (as-contract (stx-transfer? amount tx-sender contract-owner)))
        (var-set total-platform-fees (- (var-get total-platform-fees) amount))
        (ok true)
    )
)