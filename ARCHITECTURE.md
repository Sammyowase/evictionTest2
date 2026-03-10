# ARES Protocol Architecture

## Overview

ARES Protocol is a secure treasury execution system that protects against governance attacks, signature replay, flash-loan manipulation, and other exploit vectors while managing assets worth over $500 million. The system architecture, module separation, security boundaries, and trust assumptions are all covered in this document.

## System Architecture

The protocol follows a modular, defense-in-depth architecture where each component has a specific security responsibility. The core `AresTreasury` contract integrates four independent modules:

1. **ProposalModule** - Transaction proposal lifecycle management
2. **AuthorizationModule** - Cryptographic signature verification with replay protection
3. **RewardDistributionModule** - Merkle-based contributor reward distribution
4. **GovernanceDefenseModule** - Economic attack mitigation

### Module Separation Rationale

Each module is deployed as a separate contract to enforce clear security boundaries. This separation provides several benefits:

- **Isolation of Concerns**: Each module handles a specific security domain. The AuthorizationModule only manages signatures and nonces, while the ProposalModule only manages proposal state transitions.
- **Independent Upgradeability**: Modules can be upgraded independently without affecting the entire system.
- **Gas Efficiency**: Modules are only called when their functionality is needed.
- **Audit Clarity**: Security auditors can verify each module's security properties independently.

## Security Boundaries

### Proposal Lifecycle Security

The proposal system implements a three-phase lifecycle: **Pending → Committed → Queued → Executed**. Each transition has specific security requirements:

- **Pending to Committed**: Requires explicit commit with hash, establishing the proposer's intent.
- **Committed to Queued**: Requires (a) commit phase duration (24 hours) to elapse, (b) minimum number of cryptographic approvals (default 2).
- **Queued to Executed**: Requires time delay (48 hours) and must occur within execution window (7 days).

This phased approach prevents rushed executions and provides time for governance participants to review proposals.

### Cryptographic Authorization Boundary

The AuthorizationModule implements EIP-712 structured signatures with the following protections:

- **Domain Separator**: Includes chain ID and contract address to prevent cross-chain replay and domain collisions.
- **Expiry**: Each signature has a timestamp after which it cannot be used.
- **Nonce Tracking**: Per-signer nonces prevent replay of old signatures.
- **Digest Tracking**: Used digests are recorded to prevent any signature from being used twice.

The authorization boundary is strict: once a digest is marked as used, it cannot be reused regardless of nonce or expiry.

### Reward Distribution Boundary

The Merkle-based distribution system separates concerns between:

- **Round Creation**: Only treasury/governance can create distribution rounds.
- **Claim Verification**: Users must provide valid Merkle proofs; the contract only verifies, never computes.
- **State Tracking**: Claims are tracked per (roundId, index) pair to prevent double-claims.

This design allows thousands of recipients without excessive gas costs, as each claim is O(log n) in gas.

### Governance Defense Boundary

The GovernanceDefenseModule operates as a gatekeeper with two primary mechanisms:

1. **Transaction Limits**: Single transactions cannot exceed 5% of treasury balance without triggering cooldown.
2. **Holding Period**: Governance participants must hold tokens for 7 days before proposing, preventing flash-loan attacks.

These mechanisms operate at the treasury boundary, validating all outbound transfers.

## Trust Assumptions

### Minimal Trust Assumptions

1. **Governance Honesty**: The system assumes governance participants act in the protocol's best interest. However, the time delays and multi-sig requirements provide checks against individual bad actors.

2. **Economic Rationality**: The holding period and transaction limits assume attackers are economically rational and will not lock capital for extended periods.

3. **Merkle Root Integrity**: The reward distribution assumes the Merkle root provided by governance accurately reflects intended distributions. Users must trust that their claims are included.

### Trust Minimization Mechanisms

- **Time Delays**: All proposals must wait 48 hours after queueing, giving stakeholders time to react to malicious proposals.
- **Multi-Sig Approvals**: Default 2 approvals required prevents single points of failure.
- **Execution Window**: Proposals expire after 7 days, preventing stale proposals from being executed.
- **Reentrancy Guards**: All state-changing functions use reentrancy guards to prevent reentrancy attacks.

## Module Interaction Flow

```
User → AresTreasury → ProposalModule → AuthorizationModule
                           ↓
                    GovernanceDefenseModule
                           ↓
                    RewardDistributionModule
```

1. User submits proposal through AresTreasury
2. AresTreasury validates holding period via GovernanceDefenseModule
3. ProposalModule manages state transitions
4. AuthorizationModule verifies cryptographic approvals
5. GovernanceDefenseModule validates transaction limits before execution
6. RewardDistributionModule handles claims independently

## Conclusion

The ARES Protocol architecture prioritizes security through modular separation, defense-in-depth, and minimal trust assumptions. Each module enforces its own security boundary while contributing to the overall system security. The design explicitly addresses known attack vectors from recent ecosystem failures while maintaining operational flexibility for legitimate governance operations.
