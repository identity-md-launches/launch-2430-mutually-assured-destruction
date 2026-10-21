// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MADToken} from "../src/MADToken.sol";

/// @dev Test-only state machine. The ledger predicts successful calls and is unchanged by rejected calls.
contract MADTokenHandler is Test {
    MADToken private immutable token;
    address[4] private actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(MADToken token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        expectedBalance[actors_[0]] = 1_000_000_000 * 10 ** 18;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool unlimited) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        // Approval is not capped by the supply or by the owner's current balance.
        uint256 amount = unlimited ? type(uint256).max : bound(amountSeed, 0, type(uint256).max - 1);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amountSeed)
        external
    {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 approved = expectedAllowance[from][spender];
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(amountSeed, 0, balance < approved ? balance : approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        if (approved != type(uint256).max) {
            expectedAllowance[from][spender] -= amount;
        }
    }

    function rejectTransferOverBalance(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
        );
        vm.prank(from);
        token.transfer(to, amount);
    }

    function rejectTransferFromOverBalance(
        uint256 fromSeed,
        uint256 toSeed,
        uint256 spenderSeed,
        uint256 amountSeed,
        bool unlimited
    ) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        uint256 approved = unlimited ? type(uint256).max : amount;
        vm.prank(from);
        assertTrue(token.approve(spender, approved));
        expectedAllowance[from][spender] = approved;

        // Even after an allowance check succeeds, an unaffordable transfer must roll it back.
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
        );
        vm.prank(spender);
        token.transferFrom(from, to, amount);
    }

    function rejectTransferFromOverAllowance(
        uint256 fromSeed,
        uint256 toSeed,
        uint256 spenderSeed,
        uint256 allowanceSeed
    ) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 approved = bound(allowanceSeed, 0, type(uint256).max - 1);
        vm.prank(from);
        assertTrue(token.approve(spender, approved));
        expectedAllowance[from][spender] = approved;

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1
            )
        );
        vm.prank(spender);
        token.transferFrom(from, to, approved + 1);
    }

    function rejectZeroReceiver(
        uint256 fromSeed,
        uint256 spenderSeed,
        uint256 amountSeed,
        bool delegated,
        bool unlimited
    ) external {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        if (delegated) {
            uint256 approved = unlimited ? type(uint256).max : amount;
            vm.prank(from);
            assertTrue(token.approve(spender, approved));
            expectedAllowance[from][spender] = approved;
        }

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        if (delegated) {
            vm.prank(spender);
            token.transferFrom(from, address(0), amount);
        } else {
            vm.prank(from);
            token.transfer(address(0), amount);
        }
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[owner][spender] = 0;

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, 1);
    }

    function transferEntireBalance(uint256 fromSeed, uint256 toSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = expectedBalance[from];
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 96
/// forge-config: default.invariant.fail-on-revert = true
contract MADTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    MADToken private token;
    MADTokenHandler private handler;
    address[4] private actors;

    function setUp() public {
        token = new MADToken();
        actors = [makeAddr("actor 0"), makeAddr("actor 1"), makeAddr("actor 2"), makeAddr("actor 3")];
        token.transfer(actors[0], SUPPLY);
        handler = new MADTokenHandler(token, actors);

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = MADTokenHandler.transfer.selector;
        selectors[1] = MADTokenHandler.approve.selector;
        selectors[2] = MADTokenHandler.transferFrom.selector;
        selectors[3] = MADTokenHandler.rejectTransferOverBalance.selector;
        selectors[4] = MADTokenHandler.rejectTransferFromOverBalance.selector;
        selectors[5] = MADTokenHandler.rejectTransferFromOverAllowance.selector;
        selectors[6] = MADTokenHandler.rejectZeroReceiver.selector;
        selectors[7] = MADTokenHandler.rejectZeroSpender.selector;
        selectors[8] = MADTokenHandler.revoke.selector;
        selectors[9] = MADTokenHandler.transferEntireBalance.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyBalancesAndAllowancesMatchIndependentLedger() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.expectedBalance(actors[i]));
            assertEq(token.allowance(actors[i], address(0)), 0);
            assertEq(token.allowance(address(0), actors[i]), 0);
            sum += token.balanceOf(actors[i]);
            for (uint256 j; j < actors.length; ++j) {
                assertEq(
                    token.allowance(actors[i], actors[j]), handler.expectedAllowance(actors[i], actors[j])
                );
            }
        }
        assertEq(sum, SUPPLY);
    }

    /// @dev Every holder can still move its entire balance after an arbitrary sequence, including failures.
    /// A full-balance transfer around the actor ring finishes with the whole supply at actor 0.
    function afterInvariant() public {
        for (uint256 i; i < actors.length; ++i) {
            uint256 held = token.balanceOf(actors[i]);
            vm.prank(actors[i]);
            assertTrue(token.transfer(actors[(i + 1) % actors.length], held));
            assertEq(token.balanceOf(actors[i]), 0);
        }
        assertEq(token.balanceOf(actors[0]), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
