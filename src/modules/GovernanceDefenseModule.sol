// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "../libraries/AresLib.sol";

contract GovernanceDefenseModule is ReentrancyGuard {
    address public treasury;

    address public governance;

    address public pendingGovernance;

    uint256 public constant MAX_TX_BPS = 500;

    uint256 public constant LARGE_TX_COOLDOWN = 7 days;

    uint256 public largeTxThreshold = 1000;

    uint256 public lastLargeTxTime;

    uint256 public constant SNAPSHOT_DELAY = 100;

    uint256 public constant MIN_HOLDING_PERIOD = 7 days;

    mapping(uint256 => bool) public isLargeTransaction;

    mapping(address => uint256) public holdingStartTime;

    address public tokenRegistrar;

    error ExceedsTransactionLimit();

    error CooldownActive();

    error InsufficientHoldingPeriod();

    error Unauthorized();

    error InvalidGovernance();
    error TreasuryNotSet();

    event LargeTransactionProposed(uint256 indexed proposalId, uint256 amount);

    event GovernanceTransferred(address indexed oldGovernance, address indexed newGovernance);

    constructor(address _governance) {
        governance = _governance;
        holdingStartTime[_governance] = block.timestamp;
        tokenRegistrar = _governance;
    }

    function validateTransactionLimit(uint256 _amount, uint256 _treasuryBalance) external view {
        uint256 maxAllowed = (_treasuryBalance * MAX_TX_BPS) / 10000;

        if (_amount > maxAllowed) {
            if (_amount > (_treasuryBalance * largeTxThreshold) / 10000) {
                if (block.timestamp - lastLargeTxTime < LARGE_TX_COOLDOWN) {
                    revert CooldownActive();
                }
            } else {
                revert ExceedsTransactionLimit();
            }
        }
    }

    function recordLargeTransaction(uint256 _amount, uint256 _treasuryBalance) external {
        if (msg.sender != treasury) revert Unauthorized();
        if (_amount > (_treasuryBalance * largeTxThreshold) / 10000) {
            lastLargeTxTime = block.timestamp;
        }
    }

    function checkHoldingPeriod(address _caller) external view {
        if (holdingStartTime[_caller] == 0) {
            revert InsufficientHoldingPeriod();
        }
        if (block.timestamp - holdingStartTime[_caller] < MIN_HOLDING_PERIOD) {
            revert InsufficientHoldingPeriod();
        }
    }

    function recordTokenAcquisition(address _user) external {
        if (msg.sender != tokenRegistrar) revert Unauthorized();
        holdingStartTime[_user] = block.timestamp;
    }

    modifier onlyGovernance() {
        _onlyGovernance();
        _;        
    }

    function _onlyGovernance() internal view {
        if (msg.sender != governance) revert Unauthorized();
    }

    function setTreasury(address _treasury) external onlyGovernance {
        if (treasury != address(0)) revert InvalidGovernance();
        if (_treasury == address(0)) revert InvalidGovernance();
        treasury = _treasury;
    }

    function setTokenRegistrar(address _registrar) external onlyGovernance {
        if (_registrar == address(0)) revert InvalidGovernance();
        tokenRegistrar = _registrar;
    }

    function transferGovernance(address _newGovernance) external onlyGovernance {
        if (_newGovernance == address(0)) revert InvalidGovernance();
        pendingGovernance = _newGovernance;
    }

    function acceptGovernance() external {
        if (msg.sender != pendingGovernance) revert Unauthorized();

        address oldGovernance = governance;
        governance = pendingGovernance;
        pendingGovernance = address(0);

        
        holdingStartTime[governance] = block.timestamp;

        emit GovernanceTransferred(oldGovernance, governance);
    }

    function cancelGovernanceTransfer() external onlyGovernance {
        pendingGovernance = address(0);
    }

    function setLargeTxThreshold(uint256 _thresholdBps) external onlyGovernance {
        require(_thresholdBps <= 10000, "Invalid threshold");
        largeTxThreshold = _thresholdBps;
    }

    bool public isPaused;

    function pause() external onlyGovernance {
        isPaused = true;
    }

    function unpause() external onlyGovernance {
        isPaused = false;
    }

    modifier whenNotPaused() {
        _whenNotPaused();
        _;
    }

    function _whenNotPaused() internal view {
        if (isPaused) revert("Paused");
    }

    function getTreasuryBalance() external view returns (uint256) {
        if (treasury == address(0)) revert TreasuryNotSet();
        return treasury.balance;
    }
}
