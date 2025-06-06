// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../tokens/AliothReceiptToken.sol";
import "../libraries/ValidationLib.sol";

/**
 * @title ReceiptTokenFactory
 * @notice Factory for creating receipt tokens for each asset in the vault
 * @dev Only the vault can create receipt tokens
 */
contract ReceiptTokenFactory {
    using ValidationLib for address;

    /// @notice The vault contract that can create receipt tokens
    address public immutable vault;

    /// @notice Mapping from asset to receipt token
    mapping(address => address) public receiptTokens;

    /// @notice Array of all created receipt tokens
    address[] public allReceiptTokens;

    event ReceiptTokenCreated(
        address indexed asset,
        address indexed receiptToken,
        string name,
        string symbol
    );

    modifier onlyVault() {
        require(msg.sender == vault, "Only vault can call");
        _;
    }

    constructor(address _vault) {
        _vault.validateAddress();
        vault = _vault;
    }

    /**
     * @notice Create a new receipt token for an asset
     * @param asset The underlying asset address
     * @param assetSymbol The symbol of the underlying asset
     * @param assetDecimals The decimals of the underlying asset
     * @return receiptToken Address of the created receipt token
     */
    function createReceiptToken(
        address asset,
        string memory assetSymbol,
        uint8 assetDecimals
    ) external onlyVault returns (address receiptToken) {
        asset.validateAddress();
        require(
            receiptTokens[asset] == address(0),
            "Receipt token already exists"
        );

        // Create name and symbol for receipt token
        string memory name = string(abi.encodePacked("Alioth ", assetSymbol));
        string memory symbol = string(abi.encodePacked("at", assetSymbol));

        // Deploy the receipt token
        receiptToken = address(
            new AliothReceiptToken(asset, vault, name, symbol, assetDecimals)
        );

        // Store the mapping
        receiptTokens[asset] = receiptToken;
        allReceiptTokens.push(receiptToken);

        emit ReceiptTokenCreated(asset, receiptToken, name, symbol);
    }

    /**
     * @notice Get receipt token for an asset
     * @param asset The asset address
     * @return receiptToken The receipt token address (zero if not exists)
     */
    function getReceiptToken(
        address asset
    ) external view returns (address receiptToken) {
        return receiptTokens[asset];
    }

    /**
     * @notice Get all receipt tokens
     * @return tokens Array of all receipt token addresses
     */
    function getAllReceiptTokens()
        external
        view
        returns (address[] memory tokens)
    {
        return allReceiptTokens;
    }

    /**
     * @notice Get total number of receipt tokens
     * @return count Total count of receipt tokens
     */
    function getReceiptTokenCount() external view returns (uint256 count) {
        return allReceiptTokens.length;
    }
}
