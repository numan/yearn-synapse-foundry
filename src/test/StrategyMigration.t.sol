// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;

import {StrategyFixture} from "./utils/StrategyFixture.sol";

// NOTE: if the name of the strat or file changes this needs to be updated
import {Strategy} from "../Strategy.sol";

contract StrategyMigrationTest is StrategyFixture {
    function setUp() public override {
        super.setUp();
    }

    // TODO: Add tests that show proper migration of the strategy to a newer one
    // Use another copy of the strategy to simmulate the migration
    // Show that nothing is lost.
    function testMigration(uint256 _amount) public {
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
        assertRelApproxEq(
            strategy.estimatedTotalAssets(),
            _amount,
            SLIPPAGE_IN
        );

        // Migrate to a new strategy
        vm_std_cheats.prank(strategist);
        Strategy newStrategy = Strategy(deployStrategy(address(vault)));
        vm_std_cheats.prank(gov);
        vault.migrateStrategy(address(strategy), address(newStrategy));
        assertRelApproxEq(
            newStrategy.estimatedTotalAssets(),
            _amount,
            SLIPPAGE_IN
        );
    }
}
