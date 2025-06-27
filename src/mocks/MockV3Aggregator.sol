// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";

contract MockV3Aggregator is
    AggregatorV3Interface,
    AutomationCompatibleInterface
{
    uint8 public immutable override decimals;
    string public override description = "Mock Aggregator";
    uint256 public override version = 1;

    // ─── Automation Config ────────────────────────────────────────────────
    uint256 public immutable interval; // seconds between updates
    uint256 public lastTimestamp; // last time the answer was updated

    struct Round {
        int256 answer;
        uint256 updatedAt;
    }

    mapping(uint80 => Round) public rounds;
    uint80 public latestRound;

    constructor(uint8 _decimals, int256 _initialAnswer, uint256 _interval) {
        require(_interval > 0, "Interval must be > 0");
        decimals = _decimals;
        interval = _interval;
        _update(_initialAnswer);
    }

    function updateAnswer(int256 newAnswer) external {
        _update(newAnswer);
    }

    // ─── AggregatorV3Interface ─────────────────────────────
    function _update(int256 answer) internal {
        latestRound++;
        rounds[latestRound] = Round(answer, block.timestamp);

        // update timestamp used by Automation logic
        lastTimestamp = block.timestamp;
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        roundId = latestRound;
        answer = rounds[roundId].answer;
        startedAt = rounds[roundId].updatedAt;
        updatedAt = startedAt;
        answeredInRound = roundId;
    }

    // unused view fns for V2 compatibility
    function getRoundData(
        uint80
    )
        external
        pure
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        revert("not implemented");
    }

    // ─── Chainlink Automation ────────────────────────────────────────────

    /// @inheritdoc AutomationCompatibleInterface
    function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performData */)
    {
        upkeepNeeded = (block.timestamp - lastTimestamp) >= interval;
        return (upkeepNeeded, "");
    }

    /// @inheritdoc AutomationCompatibleInterface
    /// @dev The new answer is expected to be ABI-encoded `int256` in `performData`.
    function performUpkeep(bytes calldata performData) external override {
        // Ensure interval has elapsed to protect against unexpected calls
        require(
            (block.timestamp - lastTimestamp) >= interval,
            "Interval not elapsed"
        );

        int256 newAnswer = abi.decode(performData, (int256));
        _update(newAnswer);
    }
}
