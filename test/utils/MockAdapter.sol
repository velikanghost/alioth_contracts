// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import "src/interfaces/IProtocolAdapter.sol";

contract MockAdapter is IProtocolAdapter {
    uint256 private apy;

    function protocolName() external pure override returns (string memory) {
        return "Aave";
    }

    function setAPY(uint256 a) external {
        apy = a;
    }

    function getAPY(address) external view returns (uint256) {
        return apy;
    }

    function getTVL(address) external view returns (uint256) {
        return 0;
    }

    // Deposit / withdraw just emit events
    function deposit(
        address,
        uint256 amt,
        uint256
    ) external payable returns (uint256) {
        emit Deposited(msg.sender, amt, amt);
        return amt;
    }

    function withdraw(address, uint256 s, uint256) external returns (uint256) {
        emit Withdrawn(msg.sender, s, s);
        return s;
    }

    function harvestYield(address) external returns (uint256) {
        return 0;
    }

    function supportsToken(address) external view returns (bool) {
        return true;
    }

    function getSharesBalance(address) external view returns (uint256) {
        return 0;
    }

    function sharesToTokens(
        address,
        uint256 s
    ) external view returns (uint256) {
        return s;
    }

    function tokensToShares(
        address,
        uint256 a
    ) external view returns (uint256) {
        return a;
    }

    function getOperationalStatus(
        address
    ) external view returns (bool, string memory) {
        return (true, "");
    }

    function getHealthMetrics(
        address
    ) external pure returns (uint256, uint256, uint256) {
        return (0, 0, 0);
    }

    function getRiskScore(address) external pure returns (uint256) {
        return 0;
    }

    function getMaxRecommendedAllocation(
        address
    ) external pure returns (uint256) {
        return 10_000;
    }
}
