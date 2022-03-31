// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;
import "forge-std/console.sol";

import {StrategyFixture} from "./utils/StrategyFixture.sol";

contract StrategyUtilsTest is StrategyFixture {
    // setup is run on before each test
    function setUp() public override {
        // setup vault
        super.setUp();
    }

    function testcalculateAmtWithSlippageMath() public {
        uint256 _maxSlippageOut = 50;
        uint256 _wantAmt = 200 ether;
        uint256 _amtWithSlippage = strategy.calculateAmtWithSlippage(
            _wantAmt,
            _maxSlippageOut
        );
        assertEq(199 ether, _amtWithSlippage);
    }
}
