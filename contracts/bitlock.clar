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

