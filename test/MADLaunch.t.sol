// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {MADToken} from "../src/MADToken.sol";

/// @dev Test-only CREATE2 factory. It models custody and distribution, not Uniswap pool accounting.
contract MADFactoryHarness {
    function deploy(bytes32 salt) external returns (MADToken) {
        return new MADToken{salt: salt}();
    }

    function distribute(MADToken token, address distributor, address pool, address remainder) external {
        uint256 supply = token.totalSupply();
        require(token.transfer(distributor, supply / 10));
        require(token.transfer(pool, supply * 6 / 10));
        require(token.transfer(remainder, supply * 3 / 10));
    }
}

contract MADLaunchTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    function test_factoryCreate2MintDistributionClaimsAndTradingTransfers() public {
        MADFactoryHarness factory = new MADFactoryHarness();
        address origin = makeAddr("launch transaction origin");
        address distributor = makeAddr("distributor");
        address pool = makeAddr("pool custody");
        address remainder = makeAddr("remainder recipient");
        address claimant = makeAddr("contributor");
        address trader = makeAddr("trader");
        address router = makeAddr("router");
        bytes32 salt = keccak256("MAD launch test");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), address(factory), salt, keccak256(type(MADToken).creationCode)
                        )
                    )
                )
            )
        );

        vm.prank(origin, origin);
        MADToken token = factory.deploy(salt);
        assertEq(address(token), predicted);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(origin), 0);
        assertEq(token.totalSupply(), SUPPLY);

        factory.distribute(token, distributor, pool, remainder);
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(distributor), SUPPLY / 10);
        assertEq(token.balanceOf(pool), SUPPLY * 6 / 10);
        assertEq(token.balanceOf(remainder), SUPPLY * 3 / 10);

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, SUPPLY / 10));
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(claimant), SUPPLY / 10);

        // Exercise the token-side movement of a buy and an approved sell.
        uint256 bought = 123 ether;
        vm.prank(pool);
        assertTrue(token.transfer(trader, bought));
        assertEq(token.balanceOf(trader), bought);
        assertEq(token.balanceOf(pool), SUPPLY * 6 / 10 - bought);
        vm.prank(trader);
        assertTrue(token.approve(router, bought));
        vm.prank(router);
        assertTrue(token.transferFrom(trader, pool, bought));
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(pool), SUPPLY * 6 / 10);
        assertEq(token.allowance(trader, router), 0);
        assertEq(token.balanceOf(pool) + token.balanceOf(claimant) + token.balanceOf(remainder), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
