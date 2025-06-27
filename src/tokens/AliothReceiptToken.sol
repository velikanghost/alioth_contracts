// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@solmate/tokens/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../libraries/ValidationLib.sol";

/**
 * @title AliothReceiptToken
 * @notice ERC20 token representing shares in a specific asset within Alioth vault
 * @dev One receipt token per supported asset (atUSDC, atDAI, etc.)
 */
contract AliothReceiptToken is ERC20, Ownable {
    using ValidationLib for address;

    /// @notice The underlying asset this receipt token represents
    address public immutable asset;

    /// @notice The vault that can mint/burn these tokens
    address public immutable vault;

    constructor(
        address _asset,
        address _vault,
        string memory _name,
        string memory _symbol,
        uint8 _assetDecimals
    ) ERC20(_name, _symbol, _assetDecimals) Ownable(_vault) {
        _asset.validateAddress();
        _vault.validateAddress();

        asset = _asset;
        vault = _vault;
    }

    /**
     * @notice Mint receipt tokens (only vault can call)
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        to.validateAddress();
        _mint(to, amount);
    }

    /**
     * @notice Burn receipt tokens (only vault can call)
     * @param from Address to burn tokens from
     * @param amount Amount of tokens to burn
     */
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}
