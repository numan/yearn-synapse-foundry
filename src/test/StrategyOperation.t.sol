// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;
import "forge-std/console.sol";

import {StrategyFixture} from "./utils/StrategyFixture.sol";

contract StrategyOperationsTest is StrategyFixture {
    // setup is run on before each test
    function setUp() public override {
        // setup vault
        super.setUp();
    }

    function testSetupVaultOK() public {
        console.log("address of vault", address(vault));
        assertTrue(address(0) != address(vault));
        assertEq(vault.token(), address(want));
        assertEq(vault.depositLimit(), type(uint256).max);
    }

    // TODO: add additional check on strat params
    function testSetupStrategyOK() public {
        console.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(address(strategy.vault()), address(vault));
    }

    /// Test Operations
    function testStrategyOperation(uint256 _amount) public {
        vm_std_cheats.assume(
            _amount > (ONE_USDC / 10) && _amount < (ONE_USDC * 1_000_000)
        );
        tip(address(want), user, _amount);

        uint256 balanceBefore = want.balanceOf(address(user));
        vm_std_cheats.prank(user);
        want.approve(address(vault), _amount);
        vm_std_cheats.prank(user);
        vault.deposit(_amount);
        assertRelApproxEq(want.balanceOf(address(vault)), _amount, DELTA);

        skip(60 * 3); // skip 3 minutes

        vm_std_cheats.prank(strategist);
        strategy.harvest();
        assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, SLIPPAGE_IN);

        // tend
        vm_std_cheats.prank(strategist);
        strategy.tend();

        vm_std_cheats.prank(user);
        vault.withdraw();


        assertRelApproxEq(want.balanceOf(user), balanceBefore, SLIPPAGE_OUT);
    }

    function testEmergencyExit(uint256 _amount) public {
        vm_std_cheats.assume(
            _amount > (ONE_USDC / 10) && _amount < (ONE_USDC * 1_000_000)
        );
        tip(address(want), user, _amount);

        // Deposit to the vault
        vm_std_cheats.prank(user);
        want.approve(address(vault), _amount);
        vm_std_cheats.prank(user);
        vault.deposit(_amount);
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();
        assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, SLIPPAGE_IN);

        // set emergency and exit
        vm_std_cheats.prank(gov);
        strategy.setEmergencyExit();
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();
        assertEq(strategy.estimatedTotalAssets(), 0);

        assertRelApproxEq(want.balanceOf(address(vault)), _amount, SLIPPAGE_OUT);

    }

    function testEmergencyWithdraw(uint256 _amount) public {
        vm_std_cheats.assume(
            _amount > (ONE_USDC / 10) && _amount < (ONE_USDC * 1_000_000)
        );
        tip(address(want), user, _amount);

        // Deposit to the vault
        vm_std_cheats.prank(user);
        want.approve(address(vault), _amount);
        vm_std_cheats.prank(user);
        vault.deposit(_amount);

        // Harvest 1: Send funds through the strategy
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();
        assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, SLIPPAGE_IN);

        // simulate earning yield
        skip(28 days); // skip 4 weeks

        // Check we have some farm tokens to claim
        assertGt(strategy.stakedLPBalance(), 0);
        assertEq(strategy.unstakedLPBalance(), 0);

        vm_std_cheats.prank(gov);
        strategy.emergencyWithdraw();

        // Ensure all farm tokens we are entitled to have been claimed
        assertEq(strategy.stakedLPBalance(), 0);
        assertGt(strategy.unstakedLPBalance(), 0);

    }

    function testProfitableHarvest(uint256 _amount) public {
        vm_std_cheats.assume(
            _amount > (ONE_USDC / 10) && _amount < (ONE_USDC * 1_000_000)
        );
        tip(address(want), user, _amount);

        // Deposit to the vault
        vm_std_cheats.prank(user);
        want.approve(address(vault), _amount);
        vm_std_cheats.prank(user);
        vault.deposit(_amount);
        assertRelApproxEq(want.balanceOf(address(vault)), _amount, DELTA);
        uint256 beforePps = vault.pricePerShare();

        // Harvest 1: Send funds through the strategy
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();
        uint256 initialAssets = strategy.estimatedTotalAssets();
        assertRelApproxEq(initialAssets, _amount, SLIPPAGE_IN);


        // simulate earning yield
        skip(28 days); // skip 4 week


        // Harvest 2: Realize profit
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();
        skip(3600 * 6);

        uint256 profit = want.balanceOf(address(vault));
        assertGt(strategy.estimatedTotalAssets() + profit, initialAssets);
        assertGt(vault.pricePerShare(), beforePps);
    }

    function testNoSlippageAllowed() public {
        uint256 _amount = ONE_USDC * 1_000_000;

        tip(address(want), user, _amount);

        // Deposit to the vault
        vm_std_cheats.prank(user);
        want.approve(address(vault), _amount);
        vm_std_cheats.prank(user);
        vault.deposit(_amount);
        assertRelApproxEq(want.balanceOf(address(vault)), _amount, DELTA);

        // change slippage params
        vm_std_cheats.prank(gov);
        strategy.setParams(0, 0);
        assertEq(strategy.maxSlippageIn(), 0);
        assertEq(strategy.maxSlippageOut(), 0);


        // Harvest 1: Send funds through the strategy
        // Should revert because some slippage will always happen when depositing as an LP
        skip(1);
        vm_std_cheats.prank(strategist);
        vm_std_cheats.expectRevert("Couldn't mint min requested");
        strategy.harvest();

    }

    function testHarvestWithoutEnoughProfit(uint256 _amount) public {
        vm_std_cheats.assume(
            _amount > (ONE_USDC / 10) && _amount < (ONE_USDC * 1_000_000)
        );
        tip(address(want), user, _amount);

        // Deposit to the vault
        vm_std_cheats.prank(user);
        want.approve(address(vault), _amount);
        vm_std_cheats.prank(user);
        vault.deposit(_amount);
        assertRelApproxEq(want.balanceOf(address(vault)), _amount, DELTA);

        // Harvest 1: Send funds through the strategy
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();
        assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, SLIPPAGE_IN);


        // Harvest 2: Realize profit
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();
        skip(3600 * 6);

        uint256 profit = want.balanceOf(address(vault));
        assertEq(strategy.estimatedTotalAssets() + profit, strategy.estimatedTotalAssets());
    }

    function testChangeDebt(uint256 _amount) public {
        vm_std_cheats.assume(
            _amount > (ONE_USDC / 10) && _amount < (ONE_USDC * 1_000_000)
        );
        tip(address(want), user, _amount);

        // Deposit to the vault and harvest
        vm_std_cheats.prank(user);
        want.approve(address(vault), _amount);
        vm_std_cheats.prank(user);
        vault.deposit(_amount);
        vm_std_cheats.prank(gov);
        vault.updateStrategyDebtRatio(address(strategy), 5_000);
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();
        uint256 half = uint256(_amount / 2);
        assertRelApproxEq(strategy.estimatedTotalAssets(), half, SLIPPAGE_IN);

        vm_std_cheats.prank(gov);
        vault.updateStrategyDebtRatio(address(strategy), 10_000);
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();
        assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, SLIPPAGE_IN);

        vm_std_cheats.prank(gov);
        vault.updateStrategyDebtRatio(address(strategy), 5_000);
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();
        assertRelApproxEq(strategy.estimatedTotalAssets(), half, SLIPPAGE_IN);
    }

    function testSweep(uint256 _amount) public {
        vm_std_cheats.assume(
            _amount > (ONE_USDC / 10) && _amount < (ONE_USDC * 1_000_000)
        );
        tip(address(want), user, _amount);

        // Strategy want token doesn't work
        vm_std_cheats.prank(user);
        want.transfer(address(strategy), _amount);
        assertEq(address(want), address(strategy.want()));
        assertGt(want.balanceOf(address(strategy)), 0);

        vm_std_cheats.prank(gov);
        vm_std_cheats.expectRevert("!want");
        strategy.sweep(address(want));

        // Vault share token doesn't work
        vm_std_cheats.prank(gov);
        vm_std_cheats.expectRevert("!shares");
        strategy.sweep(address(vault));

        uint256 beforeBalance = weth.balanceOf(gov);
        uint256 wethAmount = 1 ether;
        tip(address(weth), user, wethAmount);
        vm_std_cheats.prank(user);
        weth.transfer(address(strategy), wethAmount);
        assertNeq(address(weth), address(strategy.want()));
        assertEq(weth.balanceOf(user), 0);
        vm_std_cheats.prank(gov);
        strategy.sweep(address(weth));
        assertRelApproxEq(
            weth.balanceOf(gov),
            wethAmount + beforeBalance,
            DELTA
        );
    }

    function testTriggers(uint256 _amount) public {
        vm_std_cheats.assume(
            _amount > (ONE_USDC / 10) && _amount < (ONE_USDC * 1_000_000)
        );
        tip(address(want), user, _amount);

        // Deposit to the vault and harvest
        vm_std_cheats.prank(user);
        want.approve(address(vault), _amount);
        vm_std_cheats.prank(user);
        vault.deposit(_amount);
        vm_std_cheats.prank(gov);
        vault.updateStrategyDebtRatio(address(strategy), 5_000);
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();

        strategy.harvestTrigger(0);
        strategy.tendTrigger(0);
    }
}
