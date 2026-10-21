// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Mutually Assured Destruction (MAD)
/// @notice A fixed-supply, 18-decimal ERC-20 for the MAD playground.
/// @dev The deploying address receives the entire supply. In the launch flow this is the factory.
///      There are no administrative powers or externally callable mint or burn functions.
contract MADToken is ERC20 {
    /// @notice One billion MAD, expressed in the token's smallest units (10^27).
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("Mutually Assured Destruction", "MAD") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
