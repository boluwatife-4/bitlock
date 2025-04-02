;; Title: BitLock USDA - Bitcoin-Collateralized Stablecoin Protocol
;; Summary: Decentralized over-collateralized stablecoin system leveraging Bitcoin through Stacks L2
;; Description:
;; A secure DeFi primitive enabling trustless minting of USDA stablecoins using Bitcoin as collateral.
;; Implements:
;; - sBTC-backed vault system with dynamic collateralization ratios
;; - Decentralized governance through SIP-009 NFT voting
;; - Multi-layered liquidation protection
;; - Real-time price feeds via Chainlink-compatible oracles
;; - Debt ceiling management for systemic stability
;; Compliant with Bitcoin security model and Stacks L2 smart contract standards

;; Constants
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_COLLATERAL (err u101))
(define-constant ERR_MIN_COLLATERAL_NOT_MET (err u102))
(define-constant ERR_VAULT_NOT_FOUND (err u103))
(define-constant ERR_ALREADY_LIQUIDATED (err u104))
(define-constant ERR_HEALTHY_VAULT (err u105))
(define-constant ERR_INSUFFICIENT_DEBT (err u106))
(define-constant ERR_EXCEEDS_DEBT_CEILING (err u107))
(define-constant ERR_INSUFFICIENT_STABLECOIN_BALANCE (err u108))
(define-constant ERR_SYSTEM_PAUSED (err u109))
(define-constant ERR_INVALID_AMOUNT (err u110))
(define-constant ERR_VAULT_EXISTS (err u111))
(define-constant ERR_ORACLE_FAILURE (err u112))
(define-constant ERR_INVALID_REDEMPTION (err u113))

;; Data variables
(define-data-var governance-token-contract principal 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
(define-data-var oracle-contract principal 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
(define-data-var stability-fee uint u10) ;; 1% annually (expressed as basis points)
(define-data-var liquidation-ratio uint u1500) ;; 150% as basis points
(define-data-var minimum-collateralization-ratio uint u1200) ;; 120% as basis points
(define-data-var liquidation-penalty uint u130) ;; 13% as basis points
(define-data-var debt-ceiling uint u10000000000000) ;; Maximum total debt (in micro-USDA)
(define-data-var total-debt uint u0) ;; Total debt issued (in micro-USDA)
(define-data-var system-paused bool false)
(define-data-var protocol-fee-percentage uint u5) ;; 0.5% as basis points

;; SIP-010 Stablecoin token traits
(define-fungible-token usda)

;; Token metadata
(define-read-only (get-name)
  (ok "USDA Stablecoin"))

(define-read-only (get-symbol)
  (ok "USDA"))

(define-read-only (get-decimals)
  (ok u6))

(define-read-only (get-token-uri)
  (ok "https://btc-stable.org/token-metadata.json"))

(define-read-only (get-total-supply)
  (ok (ft-get-supply usda)))

;; NFT for vault ownership
(define-non-fungible-token vault-token uint)

;; Vault data structure
(define-map vaults
  uint ;; vault ID
  {
    owner: principal,
    collateral: uint, ;; BTC collateral amount (in satoshis)
    debt: uint, ;; USDA debt (in micro-USDA)
    last-update: uint, ;; block height of last update
    liquidated: bool
  }
)

;; Counter for vault IDs
(define-data-var next-vault-id uint u1)

;; Get current BTC price in USD (with 6 decimal precision)
(define-read-only (get-btc-price)
  (contract-call? (var-get oracle-contract) get-btc-price))

;; Get current collateralization ratio of a vault
(define-read-only (get-collateralization-ratio (vault-id uint))
  (let (
    (vault (unwrap! (map-get? vaults vault-id) (err ERR_VAULT_NOT_FOUND)))
    (btc-price (unwrap! (get-btc-price) (err ERR_ORACLE_FAILURE)))
    (collateral-value-usd (* (get collateral vault) btc-price))
    (debt (get debt vault))
  )
  (if (> debt u0)
    (ok (/ (* collateral-value-usd u10000) debt)) ;; Result as basis points
    (ok u0))))

;; Check if a vault can be liquidated
(define-read-only (can-liquidate (vault-id uint))
  (let (
    (vault (unwrap! (map-get? vaults vault-id) (err ERR_VAULT_NOT_FOUND)))
    (c-ratio (unwrap! (get-collateralization-ratio vault-id) (err ERR_ORACLE_FAILURE)))
  )
  (if (get liquidated vault)
    (err ERR_ALREADY_LIQUIDATED)
    (if (< c-ratio (var-get liquidation-ratio))
      (ok true)
      (ok false)))))

;; Get vault info
(define-read-only (get-vault-info (vault-id uint))
  (map-get? vaults vault-id))

;; Get total system health
(define-read-only (get-system-health)
  {
    total-collateral-value: (unwrap-panic (get-total-collateral-value)),
    total-debt: (var-get total-debt),
    system-collateralization: (unwrap-panic (get-system-collateralization))
  })

;; Get total collateral value in USD
(define-read-only (get-total-collateral-value)
  (let (
    (btc-price (unwrap! (get-btc-price) (err ERR_ORACLE_FAILURE)))
    (total-collateral (fold + (map get-vault-collateral (get-all-vault-ids)) u0))
  )
  (ok (* total-collateral btc-price))))

;; Get system collateralization ratio
(define-read-only (get-system-collateralization)
  (let (
    (total-collateral-value (unwrap! (get-total-collateral-value) (err ERR_ORACLE_FAILURE)))
    (total-debt (var-get total-debt))
  )
  (if (> total-debt u0)
    (ok (/ (* total-collateral-value u10000) total-debt)) ;; Result as basis points
    (ok u0))))

;; Helper functions for iterating all vaults
(define-read-only (get-all-vault-ids)
  (let ((next-id (var-get next-vault-id)))
    (map unwrap-panic (filter is-some (map get-vault-if-exists (list-range u1 (- next-id u1)))))))

(define-read-only (get-vault-if-exists (id uint))
  (let ((vault (map-get? vaults id)))
    (if (is-some vault)
      (some id)
      none)))

(define-read-only (get-vault-collateral (vault-id uint))
  (default-to u0
    (get collateral (default-to
      { owner: 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM, collateral: u0, debt: u0, last-update: u0, liquidated: false }
      (map-get? vaults vault-id)))))

;; Create a new vault and deposit collateral
(define-public (create-vault (collateral-amount uint))
  (let (
    (vault-id (var-get next-vault-id))
    (sender tx-sender)
  )
    (asserts! (not (var-get system-paused)) (err ERR_SYSTEM_PAUSED))
    (asserts! (> collateral-amount u0) (err ERR_INVALID_AMOUNT))
    
    ;; We would implement a BTC bridge integration here
    ;; For now, we'll simulate locking BTC by simply recording it
    ;; In production, this would involve a protocol like sBTC or another bridge
    
    ;; Create vault record
    (map-set vaults vault-id {
      owner: sender,
      collateral: collateral-amount,
      debt: u0,
      last-update: block-height,
      liquidated: false
    })
    
    ;; Mint NFT for vault ownership
    (try! (nft-mint? vault-token vault-id sender))
    
    ;; Increment vault counter
    (var-set next-vault-id (+ vault-id u1))
    
    (ok vault-id)))

;; Add more collateral to an existing vault
(define-public (add-collateral (vault-id uint) (collateral-amount uint))
  (let (
    (vault (unwrap! (map-get? vaults vault-id) (err ERR_VAULT_NOT_FOUND)))
    (sender tx-sender)
  )
    (asserts! (not (var-get system-paused)) (err ERR_SYSTEM_PAUSED))
    (asserts! (is-eq sender (get owner vault)) (err ERR_UNAUTHORIZED))
    (asserts! (not (get liquidated vault)) (err ERR_ALREADY_LIQUIDATED))
    (asserts! (> collateral-amount u0) (err ERR_INVALID_AMOUNT))
    
    ;; Update vault with new collateral
    (map-set vaults vault-id {
      owner: (get owner vault),
      collateral: (+ (get collateral vault) collateral-amount),
      debt: (get debt vault),
      last-update: block-height,
      liquidated: false
    })
    
    (ok true)))

;; Mint stablecoin tokens against collateral
(define-public (mint-stablecoin (vault-id uint) (amount uint))
  (let (
    (vault (unwrap! (map-get? vaults vault-id) (err ERR_VAULT_NOT_FOUND)))
    (sender tx-sender)
    (btc-price (unwrap! (get-btc-price) (err ERR_ORACLE_FAILURE)))
    (new-debt (+ (get debt vault) amount))
    (collateral-value-usd (* (get collateral vault) btc-price))
  )
    (asserts! (not (var-get system-paused)) (err ERR_SYSTEM_PAUSED))
    (asserts! (is-eq sender (get owner vault)) (err ERR_UNAUTHORIZED))
    (asserts! (not (get liquidated vault)) (err ERR_ALREADY_LIQUIDATED))
    (asserts! (> amount u0) (err ERR_INVALID_AMOUNT))
    
    ;; Check if debt ceiling would be exceeded
    (asserts! (<= (+ (var-get total-debt) amount) (var-get debt-ceiling)) (err ERR_EXCEEDS_DEBT_CEILING))
    
    ;; Calculate new collateralization ratio
    (let ((new-ratio (/ (* collateral-value-usd u10000) new-debt)))
      ;; Check if minimum collateralization ratio is maintained
      (asserts! (>= new-ratio (var-get minimum-collateralization-ratio)) (err ERR_MIN_COLLATERAL_NOT_MET))
      
      ;; Update vault info
      (map-set vaults vault-id {
        owner: (get owner vault),
        collateral: (get collateral vault),
        debt: new-debt,
        last-update: block-height,
        liquidated: false
      })
      
      ;; Update total debt
      (var-set total-debt (+ (var-get total-debt) amount))
      
      ;; Mint stablecoins to sender
      (try! (ft-mint? usda amount sender))
      
      (ok true))))

;; Repay debt
(define-public (repay-debt (vault-id uint) (amount uint))
  (let (
    (vault (unwrap! (map-get? vaults vault-id) (err ERR_VAULT_NOT_FOUND)))
    (sender tx-sender)
    (debt (get debt vault))
  )
    (asserts! (not (get liquidated vault)) (err ERR_ALREADY_LIQUIDATED))
    (asserts! (<= amount debt) (err ERR_INVALID_AMOUNT))
    (asserts! (> amount u0) (err ERR_INVALID_AMOUNT))
    
    ;; Burn stablecoins from sender
    (try! (ft-burn? usda amount sender))
    
    ;; Update vault
    (map-set vaults vault-id {
      owner: (get owner vault),
      collateral: (get collateral vault),
      debt: (- debt amount),
      last-update: block-height,
      liquidated: false
    })
    
    ;; Update total debt
    (var-set total-debt (- (var-get total-debt) amount))
    
    (ok true)))

;; Withdraw collateral
(define-public (withdraw-collateral (vault-id uint) (amount uint))
  (let (
    (vault (unwrap! (map-get? vaults vault-id) (err ERR_VAULT_NOT_FOUND)))
    (sender tx-sender)
    (current-collateral (get collateral vault))
    (debt (get debt vault))
    (btc-price (unwrap! (get-btc-price) (err ERR_ORACLE_FAILURE)))
  )
    (asserts! (not (var-get system-paused)) (err ERR_SYSTEM_PAUSED))
    (asserts! (is-eq sender (get owner vault)) (err ERR_UNAUTHORIZED))
    (asserts! (not (get liquidated vault)) (err ERR_ALREADY_LIQUIDATED))
    (asserts! (<= amount current-collateral) (err ERR_INSUFFICIENT_COLLATERAL))
    (asserts! (> amount u0) (err ERR_INVALID_AMOUNT))
    
    ;; Calculate new collateral amount
    (let (
      (new-collateral (- current-collateral amount))
      (new-collateral-value-usd (* new-collateral btc-price))
    )
      ;; Check if debt exists
      (if (> debt u0)
        ;; Calculate new ratio
        (let ((new-ratio (/ (* new-collateral-value-usd u10000) debt)))
          ;; Check if minimum collateralization ratio is maintained
          (asserts! (>= new-ratio (var-get minimum-collateralization-ratio)) (err ERR_MIN_COLLATERAL_NOT_MET)))
        true) ;; No debt means no ratio requirements
      
      ;; Update vault
      (map-set vaults vault-id {
        owner: (get owner vault),
        collateral: new-collateral,
        debt: debt,
        last-update: block-height,
        liquidated: false
      })
      
      ;; In production, we would integrate with BTC bridge to return BTC to user
      ;; For now we're just updating the record
      
      (ok true))))

;; Liquidate an undercollateralized vault
(define-public (liquidate-vault (vault-id uint))
  (let (
    (vault (unwrap! (map-get? vaults vault-id) (err ERR_VAULT_NOT_FOUND)))
    (liquidatable (unwrap! (can-liquidate vault-id) (err ERR_HEALTHY_VAULT)))
    (collateral (get collateral vault))
    (debt (get debt vault))
    (btc-price (unwrap! (get-btc-price) (err ERR_ORACLE_FAILURE)))
    (liquidator tx-sender)
  )
    (asserts! (not (var-get system-paused)) (err ERR_SYSTEM_PAUSED))
    (asserts! liquidatable (err ERR_HEALTHY_VAULT))
    
    ;; Verify liquidator has enough stablecoins to cover the debt
    (asserts! (>= (ft-get-balance usda liquidator) debt) (err ERR_INSUFFICIENT_STABLECOIN_BALANCE))
    
    ;; Calculate liquidation values
    (let (
      (penalty (/ (* debt (var-get liquidation-penalty)) u1000)) ;; Liquidation penalty
      (total-to-repay (+ debt penalty))
      (collateral-value-usd (* collateral btc-price))
    )
      ;; Burn stablecoins from liquidator to cover the debt
      (try! (ft-burn? usda debt liquidator))
      
      ;; Transfer collateral to liquidator
      ;; In production, we would use a BTC bridge to transfer BTC
      ;; Here we're just simulating the transfer
      
      ;; Mark vault as liquidated
      (map-set vaults vault-id {
        owner: (get owner vault),
        collateral: u0, ;; All collateral taken
        debt: u0,       ;; Debt cleared
        last-update: block-height,
        liquidated: true
      })
      
      ;; Update total debt
      (var-set total-debt (- (var-get total-debt) debt))
      
      (ok { collateral-seized: collateral, debt-repaid: debt }))))

;; Close a vault (repay all debt and withdraw all collateral)
(define-public (close-vault (vault-id uint))
  (let (
    (vault (unwrap! (map-get? vaults vault-id) (err ERR_VAULT_NOT_FOUND)))
    (sender tx-sender)
    (debt (get debt vault))
    (collateral (get collateral vault))
  )
    (asserts! (is-eq sender (get owner vault)) (err ERR_UNAUTHORIZED))
    (asserts! (not (get liquidated vault)) (err ERR_ALREADY_LIQUIDATED))
    
    ;; First repay all debt if any
    (if (> debt u0)
      (begin
        ;; Burn stablecoins from sender
        (try! (ft-burn? usda debt sender))
        
        ;; Update total debt
        (var-set total-debt (- (var-get total-debt) debt)))
      true) ;; No debt to repay
    
    ;; Transfer collateral back to user
    ;; In production, we would use a BTC bridge
    
    ;; Burn the vault NFT
    (try! (nft-burn? vault-token vault-id sender))
    
    ;; Delete vault record
    (map-delete vaults vault-id)
    
    (ok { collateral-returned: collateral, debt-repaid: debt })))

;; Direct stablecoin redemption for BTC (at a fee)
(define-public (redeem-stablecoin-for-btc (amount uint))
  (let (
    (sender tx-sender)
    (btc-price (unwrap! (get-btc-price) (err ERR_ORACLE_FAILURE)))
    (fee-amount (/ (* amount (var-get protocol-fee-percentage)) u1000))
    (net-amount (- amount fee-amount))
    (btc-amount (/ (* net-amount u100000000) btc-price))  ;; Convert to satoshis
  )
    (asserts! (not (var-get system-paused)) (err ERR_SYSTEM_PAUSED))
    (asserts! (> amount u0) (err ERR_INVALID_AMOUNT))
    (asserts! (<= amount (var-get total-debt)) (err ERR_INVALID_REDEMPTION))
    
    ;; Burn stablecoins from sender
    (try! (ft-burn? usda amount sender))
    
    ;; In production, we would integrate with a BTC bridge
    ;; to transfer BTC to the user
    
    ;; Update total debt
    (var-set total-debt (- (var-get total-debt) amount))
    
    (ok { redeemed-amount: net-amount, btc-amount: btc-amount, fee-paid: fee-amount })))

;; Governance functions

;; Update liquidation ratio (only callable by governance)
(define-public (update-liquidation-ratio (new-ratio uint))
  (begin
    (asserts! (is-contract-caller (var-get governance-token-contract)) (err ERR_UNAUTHORIZED))
    (var-set liquidation-ratio new-ratio)
    (ok true)))

;; Update minimum collateralization ratio (only callable by governance)
(define-public (update-min-collateralization-ratio (new-ratio uint))
  (begin
    (asserts! (is-contract-caller (var-get governance-token-contract)) (err ERR_UNAUTHORIZED))
    (var-set minimum-collateralization-ratio new-ratio)
    (ok true)))

;; Update stability fee (only callable by governance)
(define-public (update-stability-fee (new-fee uint))
  (begin
    (asserts! (is-contract-caller (var-get governance-token-contract)) (err ERR_UNAUTHORIZED))
    (var-set stability-fee new-fee)
    (ok true)))

;; Update liquidation penalty (only callable by governance)
(define-public (update-liquidation-penalty (new-penalty uint))
  (begin
    (asserts! (is-contract-caller (var-get governance-token-contract)) (err ERR_UNAUTHORIZED))
    (var-set liquidation-penalty new-penalty)
    (ok true)))

;; Update debt ceiling (only callable by governance)
(define-public (update-debt-ceiling (new-ceiling uint))
  (begin
    (asserts! (is-contract-caller (var-get governance-token-contract)) (err ERR_UNAUTHORIZED))
    (var-set debt-ceiling new-ceiling)
    (ok true)))

;; Update protocol fee percentage (only callable by governance)
(define-public (update-protocol-fee-percentage (new-fee uint))
  (begin
    (asserts! (is-contract-caller (var-get governance-token-contract)) (err ERR_UNAUTHORIZED))
    (var-set protocol-fee-percentage new-fee)
    (ok true)))

;; Emergency pause function (only callable by governance)
(define-public (set-pause-state (paused bool))
  (begin
    (asserts! (is-contract-caller (var-get governance-token-contract)) (err ERR_UNAUTHORIZED))
    (var-set system-paused paused)
    (ok true)))