;; contract title: AI-Based Gas Fee Optimization Manager (Extended)
;; This contract allows authorized AI agents to update network gas metrics and provides
;; optimized gas fee recommendations based on historical data and current congestion levels.
;; It acts as an on-chain registry for off-chain AI analysis results.
;;
;; Features:
;; - AI Agent Authorization
;; - Historical Gas Data Tracking (Circular Buffer)
;; - Multiple Optimization Strategies (Conservative, Balanced, Aggressive)
;; - Granular Admin Controls for Multipliers
;; - Pausable Contract State
;; - Smart Strategy Selection

;; ---------------------------------------------------------------------------------
;; Constants & Error Codes
;; ---------------------------------------------------------------------------------

(define-constant contract-owner tx-sender)

;; Error Codes
(define-constant err-owner-only (err u100))
(define-constant err-unauthorized-agent (err u101))
(define-constant err-invalid-metric (err u102))
(define-constant err-data-not-found (err u103))
(define-constant err-contract-paused (err u104))
(define-constant err-invalid-param (err u105))

;; Strategy Constants
(define-constant strategy-conservative u1)
(define-constant strategy-balanced u2)
(define-constant strategy-aggressive u3)

;; Buffer Size for Historical Analysis
(define-constant history-buffer-size u5)

;; ---------------------------------------------------------------------------------
;; Data Maps and Variables
;; ---------------------------------------------------------------------------------

;; Stores authorized AI agents that can submit gas metrics
(define-map authorized-ai-agents principal bool)

;; Stores historical gas metrics for analysis
;; Key: block-height, Value: {avg-fee: uint, congestion-level: uint}
(define-map historical-gas-metrics 
    uint 
    {avg-fee: uint, congestion-level: uint}
)

;; The most recent base fee reported by an AI agent
(define-data-var current-base-fee uint u1000)

;; The most recent network congestion level (1-100) reported by an AI agent
(define-data-var current-congestion-level uint u50)

;; Contract paused state (emergency switch)
(define-data-var contract-paused bool false)

;; Circular Buffer Index
(define-data-var buffer-index uint u0)

;; Store recent gas metrics for Moving Average Calculation
;; Key: Index (0-4), Value: fee
(define-map recent-gas-fees uint uint)

;; ---------------------------------------------------------------------------------
;; Configuration Variables (Admin Validated)
;; ---------------------------------------------------------------------------------

;; Conservative Strategy Multipliers (scaled by 100)
(define-data-var conservative-base-multiplier uint u110) ;; 1.1x

;; Balanced Strategy Multipliers
(define-data-var balanced-low-congestion-mult uint u120) ;; 1.2x
(define-data-var balanced-med-congestion-mult uint u150) ;; 1.5x
(define-data-var balanced-high-congestion-mult uint u200) ;; 2.0x

;; Aggressive Strategy Multipliers
(define-data-var aggressive-base-multiplier uint u200) ;; 2.0x
(define-data-var aggressive-surge-multiplier uint u300) ;; 3.0x

;; Congestion Thresholds
(define-data-var threshold-moderate uint u50)
(define-data-var threshold-high uint u80)

;; ---------------------------------------------------------------------------------
;; Private Functions
;; ---------------------------------------------------------------------------------

;; Checks if the caller is the contract owner
(define-private (is-contract-owner)
    (is-eq tx-sender contract-owner)
)

;; Checks if the caller is an authorized AI agent
(define-private (is-authorized-agent (agent principal))
    (default-to false (map-get? authorized-ai-agents agent))
)

;; Checks if the contract is active
(define-private (check-active)
    (or (not (var-get contract-paused)) (is-contract-owner))
)

;; Helper to record history in circular buffer
(define-private (record-metric-history (fee uint))
    (let
        (
            (idx (var-get buffer-index))
            (next-idx (mod (+ idx u1) history-buffer-size))
        )
        (map-set recent-gas-fees idx fee)
        (var-set buffer-index next-idx)
    )
)

;; Helper to calculate average of last 5 blocks
;; Since we cannot loop easily, we manually sum the map entries
(define-private (get-moving-average)
    (let
        (
            (v0 (default-to u0 (map-get? recent-gas-fees u0)))
            (v1 (default-to u0 (map-get? recent-gas-fees u1)))
            (v2 (default-to u0 (map-get? recent-gas-fees u2)))
            (v3 (default-to u0 (map-get? recent-gas-fees u3)))
            (v4 (default-to u0 (map-get? recent-gas-fees u4)))
        )
        (/ (+ v0 (+ v1 (+ v2 (+ v3 v4)))) history-buffer-size)
    )
)

;; ---------------------------------------------------------------------------------
;; Admin Functions
;; ---------------------------------------------------------------------------------

(define-public (add-authorized-agent (agent principal))
    (begin
        (asserts! (is-contract-owner) err-owner-only)
        (ok (map-set authorized-ai-agents agent true))
    )
)

(define-public (set-paused (state bool))
    (begin
        (asserts! (is-contract-owner) err-owner-only)
        (ok (var-set contract-paused state))
    )
)

;; Configuration Setters
(define-public (set-conservative-config (multiplier uint))
    (begin
        (asserts! (is-contract-owner) err-owner-only)
        (asserts! (>= multiplier u100) err-invalid-param)
        (ok (var-set conservative-base-multiplier multiplier))
    )
)

(define-public (set-balanced-config (low uint) (med uint) (high uint))
    (begin
        (asserts! (is-contract-owner) err-owner-only)
        (asserts! (and (>= low u100) (>= med low) (>= high med)) err-invalid-param)
        (var-set balanced-low-congestion-mult low)
        (var-set balanced-med-congestion-mult med)
        (var-set balanced-high-congestion-mult high)
        (ok true)
    )
)

(define-public (set-aggressive-config (base uint) (surge uint))
    (begin
        (asserts! (is-contract-owner) err-owner-only)
        (asserts! (and (>= base u100) (>= surge base)) err-invalid-param)
        (var-set aggressive-base-multiplier base)
        (var-set aggressive-surge-multiplier surge)
        (ok true)
    )
)

(define-public (set-congestion-thresholds (moderate uint) (high uint))
    (begin
        (asserts! (is-contract-owner) err-owner-only)
        (asserts! (and (> moderate u0) (> high moderate) (<= high u100)) err-invalid-param)
        (var-set threshold-moderate moderate)
        (var-set threshold-high high)
        (ok true)
    )
)

;; ---------------------------------------------------------------------------------
;; Core Logic Functions
;; ---------------------------------------------------------------------------------

;; Allows an authorized AI agent to update network metrics
(define-public (update-network-metrics (new-base-fee uint) (new-congestion uint))
    (begin
        (asserts! (check-active) err-contract-paused)
        (asserts! (is-authorized-agent tx-sender) err-unauthorized-agent)
        (asserts! (and (> new-base-fee u0) (<= new-congestion u100)) err-invalid-metric)
        
        ;; Update contract state
        (var-set current-base-fee new-base-fee)
        (var-set current-congestion-level new-congestion)
        
        ;; Save to history
        (map-set historical-gas-metrics 
            block-height 
            {avg-fee: new-base-fee, congestion-level: new-congestion}
        )
        
        ;; Update circular buffer for moving average
        (record-metric-history new-base-fee)
        
        (ok true)
    )
)

;; ---------------------------------------------------------------------------------
;; Strategy Implementations
;; ---------------------------------------------------------------------------------

;; Strategy 1: Conservative
;; Best for non-urgent transactions, aims to save costs.
;; Logic: Uses a small fixed multiplier above base fee.
(define-read-only (calculate-conservative-fee (base-fee uint))
    (let
        (
            (mult (var-get conservative-base-multiplier))
        )
        (ok (/ (* base-fee mult) u100))
    )
)

;; Strategy 2: Balanced
;; Adapts to network conditions.
;; Logic: Scales multiplier based on current congestion levels.
(define-read-only (calculate-balanced-fee (base-fee uint) (congestion uint))
    (let
        (
            (moderate (var-get threshold-moderate))
            (high (var-get threshold-high))
            (mult (if (> congestion high)
                      (var-get balanced-high-congestion-mult)
                      (if (> congestion moderate)
                          (var-get balanced-med-congestion-mult)
                          (var-get balanced-low-congestion-mult)
                      )
                  ))
        )
        (ok (/ (* base-fee mult) u100))
    )
)

;; Strategy 3: Aggressive
;; For urgent transactions that must be included in the next block.
;; Logic: Uses high base multiplier + massive surge if congestion is high.
(define-read-only (calculate-aggressive-fee (base-fee uint) (congestion uint))
    (let
        (
            (high-thresh (var-get threshold-high))
            (mult (if (> congestion high-thresh)
                      (var-get aggressive-surge-multiplier)
                      (var-get aggressive-base-multiplier)
                  ))
        )
        (ok (/ (* base-fee mult) u100))
    )
)

;; ---------------------------------------------------------------------------------
;; Reporting & Analysis Features
;; ---------------------------------------------------------------------------------

;; Returns a comparison of all strategies for the current network state
(define-read-only (get-strategy-comparison)
    (let
        (
            (base (var-get current-base-fee))
            (cong (var-get current-congestion-level))
            (cons (unwrap-panic (calculate-conservative-fee base)))
            (bal (unwrap-panic (calculate-balanced-fee base cong)))
            (agg (unwrap-panic (calculate-aggressive-fee base cong)))
        )
        (ok {
            conservative: cons,
            balanced: bal,
            aggressive: agg,
            base-fee: base,
            congestion: cong,
            moving-avg-5-blk: (get-moving-average)
        })
    )
)

;; ---------------------------------------------------------------------------------
;; AI-Driven Dynamic Fee Calculation Feature (Main Feature)
;; ---------------------------------------------------------------------------------

;; This consolidated function acts as a smart router. It takes a user priority
;; and automatically maps it to the best strategy, applying additional logic
;; derived from historical trends.
;;
;; If the network is rapidly becoming congested (current fee > moving average),
;; it boosts the balanced strategy slightly to ensure inclusion.
;;
;; Inputs:
;; - priority-level: A user-defined priority (1=Low/Conservative, 2=Medium/Balanced, 3=High/Aggressive)
;;
;; Returns: 
;; - (ok uint): The calculated optimal gas fee
(define-read-only (calculate-dynamic-optimal-fee (priority-level uint))
    (let
        (
            (base (var-get current-base-fee))
            (cong (var-get current-congestion-level))
            (avg (get-moving-average))
            
            ;; Detect trend: Is fee rising?
            ;; If current base > avg, fees are rising.
            (trend-rising (> base avg))
        )
        
        ;; Select Strategy
        (if (is-eq priority-level u1)
            ;; Priority 1: Conservative
            (calculate-conservative-fee base)
            
            (if (is-eq priority-level u2)
                ;; Priority 2: Balanced + Trend Boost
                (let
                    (
                        (raw-fee (unwrap-panic (calculate-balanced-fee base cong)))
                        ;; If fees are rising, add 5% buffer to balanced strategy
                        (final-fee (if trend-rising
                                       (/ (* raw-fee u105) u100)
                                       raw-fee))
                    )
                    (ok final-fee)
                )
                
                (if (is-eq priority-level u3)
                    ;; Priority 3: Aggressive
                    (calculate-aggressive-fee base cong)
                    
                    ;; Default: Balanced
                    (calculate-balanced-fee base cong)
                )
            )
        )
    )
)


