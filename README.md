# ARES Protocol

## Advanced Treasury Execution System

ARES Protocol is a secure treasury management system designed to manage $500M+ in assets while defending against governance attacks, signature replay, flash-loan manipulation, and other exploit vectors.

## Features

- **Multi-Phase Proposal System**: Proposals go through Pending → Committed → Queued → Executed phases with mandatory delays
- **Cryptographic Authorization**: EIP-712 structured signatures with replay protection
- **Time-Delayed Execution**: 48-hour minimum delay between queueing and execution
- **Merkle-Based Rewards**: Scalable contributor reward distribution with O(log n) gas cost
- **Governance Attack Mitigation**: Flash-loan protection and large transaction limits

## Architecture

```
src/
├── interfaces/
│   ├── IAresTreasury.sol      # Core treasury interface
│   ├── IAuthorization.sol     # Authorization layer interface
│   └── IRewardDistributor.sol # Reward distribution interface
├── libraries/
│   └── AresLib.sol            # Security utilities and helpers
├── modules/
│   ├── AuthorizationModule.sol      # Signature verification
│   ├── ProposalModule.sol           # Proposal lifecycle
│   ├── RewardDistributionModule.sol # Merkle rewards
│   └── GovernanceDefenseModule.sol  # Attack mitigation
└── core/
    └── AresTreasury.sol     # Main treasury contract
```

## Security Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| `MIN_DELAY` | 48 hours | Time between queue and execution |
| `COMMIT_PHASE` | 24 hours | Commit phase duration |
| `EXECUTION_WINDOW` | 7 days | Window to execute queued proposal |
| `MAX_TX_BPS` | 500 (5%) | Max single transaction limit |
| `LARGE_TX_COOLDOWN` | 7 days | Cooldown between large transactions |
| `MIN_HOLDING_PERIOD` | 7 days | Token holding period for proposals |
| `minApprovals` | 2 | Required proposal approvals |

## Attack Mitigations

| Attack Vector | Mitigation |
|--------------|------------|
| Signature Replay | Digest tracking + nonces + expiry + chain ID |
| Flash-Loan Governance | 7-day holding period requirement |
| Treasury Drain | 5% transaction limit + 7-day cooldown |
| Reentrancy | Reentrancy guards on all state-changing functions |
| Double Claim | Per-round claim tracking |
| Cross-Chain Replay | Chain ID binding in signatures |
| Timelock Bypass | Explicit state machine with timestamps |

## Test Coverage

**Negative Tests (Exploit Prevention):**
1. Double claim attack.
2. Invalid signature approval.
3. Premature execution.
4. Unauthorized cancellation.
5. Execution window expiry.
6. Commit phase bypass.
7. Insufficient approvals.
8. Flash-loan governance attack.


## Documentation

- [Architecture](ARCHITECTURE.md) - System design and module separation
- [Security Analysis](SECURITY.md) - Attack surface analysis and mitigations

## Protocol Specification

### Proposal Lifecycle

1. **Creation**: User creates proposal with type, target, amount, and data
2. **Commitment**: Proposer commits with hash, starting 24-hour commit phase
3. **Approval**: Approvers provide cryptographic signatures (minimum 2 required)
4. **Queueing**: After commit phase and approvals, proposal can be queued
5. **Delay**: 48-hour delay before execution is allowed
6. **Execution**: Proposal can be executed within 7-day window
7. **Completion**: Proposal marked as executed or expired


## License

MIT

