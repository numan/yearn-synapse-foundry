// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;

import {StrategyFixture} from "./utils/StrategyFixture.sol";

contract StrategyRevokeTest is StrategyFixture {
    function setUp() public override {
        super.setUp();
    }

    function testRevokeStrategyFromVault(uint256 _amount) public {
        vm_std_cheats.assume(
            _amount > (ONE_USDC / 10) && _amount < (ONE_USDC * 1_000_000)
        );
        tip(address(want), user, _amount);

        // Deposit to the vault and harvest
        vm_std_cheats.prank(user);
        want.approve(address(vault), _amount);
        vm_std_cheats.prank(user);
        vault.deposit(_amount);
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();
        assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, SLIPPAGE_IN);

        // In order to pass these tests, you will need to implement prepareReturn.
        vm_std_cheats.prank(gov);
        vault.revokeStrategy(address(strategy));
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();
        assertRelApproxEq(want.balanceOf(address(vault)), _amount, SLIPPAGE_IN);
    }

    function testRevokeStrategyFromStrategy(uint256 _amount) public {
        vm_std_cheats.assume(
            _amount > (ONE_USDC / 10) && _amount < (ONE_USDC * 1_000_000)
        );
        tip(address(want), user, _amount);

        vm_std_cheats.prank(user);
        want.approve(address(vault), _amount);
        vm_std_cheats.prank(user);
        vault.deposit(_amount);
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();
        assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, SLIPPAGE_IN);

        vm_std_cheats.prank(gov);
        strategy.setEmergencyExit();
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();
        assertRelApproxEq(want.balanceOf(address(vault)), _amount, SLIPPAGE_IN);
    }
}
