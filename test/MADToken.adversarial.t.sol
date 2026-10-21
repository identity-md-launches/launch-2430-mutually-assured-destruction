// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MADToken} from "../src/MADToken.sol";

/// @dev An ERC-20 recipient need not implement hooks, a fallback, or any token interface.
contract MADPassiveRecipient {}

/// forge-config: default.fuzz.runs = 1024
contract MADTokenAdversarialTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    MADToken private token;
    address private alice;
    address private bob;
    address private spender;

    function setUp() public {
        token = new MADToken();
        alice = makeAddr("adversarial alice");
        bob = makeAddr("adversarial bob");
        spender = makeAddr("adversarial spender");
    }

    function test_oneWeiCanBeTransferredApprovedAndSpent() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumTransferRevertsWithoutOverflowOrStateChange() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(bob, type(uint256).max);
        _assertInitialBalances();
    }

    function test_maximumDelegatedTransferFailsAtAllowanceBoundary() public {
        token.approve(spender, type(uint256).max - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                spender,
                type(uint256).max - 1,
                type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), bob, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max - 1);
        _assertInitialBalances();
    }

    function test_unlimitedApprovalCannotSpendMoreThanBalance() public {
        token.approve(spender, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), bob, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        _assertInitialBalances();
    }

    function test_largestFiniteApprovalIsDecremented() public {
        token.approve(spender, type(uint256).max - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, SUPPLY));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 1 - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(bob), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_exhaustedAllowanceCannotBeReplayedWhileOwnerStillHasFunds() public {
        token.approve(spender, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 1));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(bob), 1);
    }

    function test_unlimitedApprovalCanBeRevokedAndReplacedByFiniteApproval() public {
        token.approve(spender, type(uint256).max);
        token.approve(spender, 0);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), 0);
        _assertInitialBalances();

        token.approve(spender, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 1));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_ownerCallingTransferFromStillNeedsApproval() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1)
        );
        token.transferFrom(address(this), bob, 1);
        _assertInitialBalances();

        token.approve(address(this), 1);
        assertTrue(token.transferFrom(address(this), bob, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(bob), 1);
    }

    function test_delegatedSelfTransferStillChecksBalanceAndRestoresAllowance() public {
        token.approve(spender, SUPPLY + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), address(this), SUPPLY + 1);
        assertEq(token.allowance(address(this), spender), SUPPLY + 1);
        _assertInitialBalances();
    }

    function test_zeroDelegatedTransferToZeroReceiverStillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(alice, address(0), 0);
        assertEq(token.allowance(alice, spender), 0);
        _assertInitialBalances();
    }

    function test_zeroApprovalToZeroSpenderStillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        _assertInitialBalances();
    }

    function test_contractRecipientNeedsNoCallbackForDirectOrDelegatedTransfer() public {
        MADPassiveRecipient recipient = new MADPassiveRecipient();
        assertTrue(token.transfer(address(recipient), 1));
        token.approve(spender, SUPPLY - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(recipient), SUPPLY - 1));
        assertEq(token.balanceOf(address(recipient)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_approvalReplacementAndSpendingUseFullUint256Range(
        uint256 firstApproval,
        uint256 replacement,
        uint256 amountSeed
    ) public {
        assertTrue(token.approve(spender, firstApproval));
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);
        _assertInitialBalances();

        uint256 amount = bound(amountSeed, 0, replacement < SUPPLY ? replacement : SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, amount));
        uint256 remaining = replacement == type(uint256).max ? replacement : replacement - amount;
        assertEq(token.allowance(address(this), spender), remaining);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_zeroDelegatedTransferPreservesAnyExistingApproval(uint256 approved) public {
        // An unfunded owner may approve a future spend, including an unlimited one.
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), approved);
        _assertInitialBalances();
    }

    function testFuzz_failedDelegatedTransferCanBeRetriedAfterFunding(
        uint256 balanceSeed,
        uint256 amountSeed,
        bool unlimited
    ) public {
        uint256 balance = bound(balanceSeed, 0, SUPPLY - 1);
        uint256 amount = bound(amountSeed, balance + 1, SUPPLY);
        token.transfer(alice, balance);
        uint256 approved = unlimited ? type(uint256).max : amount;
        vm.prank(alice);
        token.approve(spender, approved);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);

        token.transfer(alice, amount - balance);
        // No re-approval: the failed call must not consume the holder's authorization.
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.allowance(alice, spender), unlimited ? type(uint256).max : 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_rejectedZeroRecipientDoesNotConsumeAuthorization(
        uint256 amountSeed,
        uint256 allowanceSeed,
        bool unlimited
    ) public {
        uint256 amount = bound(amountSeed, 0, SUPPLY);
        uint256 approved = unlimited ? type(uint256).max : bound(allowanceSeed, amount, type(uint256).max - 1);
        token.approve(spender, approved);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), approved);
        _assertInitialBalances();

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, amount));
        assertEq(token.allowance(address(this), spender), unlimited ? approved : approved - amount);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
    }

    function testFuzz_splitDelegatedSpendingMatchesOneCombinedTransfer(uint256 totalSeed, uint256 firstSeed)
        public
    {
        uint256 total = bound(totalSeed, 1, SUPPLY);
        uint256 first = bound(firstSeed, 0, total);
        token.approve(spender, total);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, first));
        assertEq(token.allowance(address(this), spender), total - first);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, total - first));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(bob), total);
        assertEq(token.balanceOf(address(this)), SUPPLY - total);
        assertEq(token.totalSupply(), SUPPLY);

        // Transferring the aggregate back restores the starting balances without restoring allowance.
        vm.prank(bob);
        assertTrue(token.transfer(address(this), total));
        _assertInitialBalances();
        assertEq(token.allowance(address(this), spender), 0);
    }

    function testFuzz_delegatedTransferSupportsEveryAddressAlias(
        uint8 aliasSeed,
        uint256 amountSeed,
        bool unlimited
    ) public {
        // Exercise all five partitions of {owner, recipient, spender}, including all equal.
        uint256 mode = aliasSeed % 5;
        address recipient = mode == 1 || mode == 4 ? address(this) : bob;
        address caller = mode == 2 || mode == 4 ? address(this) : mode == 3 ? bob : spender;
        token.transfer(bob, 17);
        uint256 amount = bound(amountSeed, 0, SUPPLY - 17);
        uint256 approved = unlimited ? type(uint256).max : amount;
        token.approve(caller, approved);
        vm.prank(caller);
        assertTrue(token.transferFrom(address(this), recipient, amount));
        assertEq(
            token.balanceOf(address(this)), recipient == address(this) ? SUPPLY - 17 : SUPPLY - 17 - amount
        );
        assertEq(token.balanceOf(bob), recipient == bob ? 17 + amount : 17);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(address(this), caller), unlimited ? type(uint256).max : 0);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(bob), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _assertInitialBalances() private view {
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
