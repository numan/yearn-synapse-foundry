// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;

// NOTE: if the name of the strat or file changes this needs to be updated
import {Strategy} from "../../Strategy.sol";

contract StrategyWrapper is Strategy {
    constructor(
        address _vault,
        address _synStable3PoolLP,
        address _synStable3Pool,
        address _solidlyRouter,
        address _synStakingMC,
        uint256 _stakingContractPoolId,
        uint8 _synStable3PoolUSDCTokenIndex,
        uint256 _maxSlippageIn,
        uint256 _maxSlippageOut
    )
        Strategy(
            _vault,
            _synStable3PoolLP,
            _synStable3Pool,
            _solidlyRouter,
            _synStakingMC,
            _stakingContractPoolId,
            _synStable3PoolUSDCTokenIndex,
            _maxSlippageIn,
            _maxSlippageOut
        )
    {}

    function calculateAmtWithSlippage(uint256 _amount, uint256 slippage)
        public
        pure
        returns (uint256)
    {
        return super._calculateAmtWithSlippage(_amount, slippage);
    }
}
