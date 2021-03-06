// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

pragma solidity ^0.8.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {BaseStrategy, StrategyParams} from "@yearnvaults/contracts/BaseStrategy.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ISwap} from "./interfaces/synapse/ISwap.sol";
import {IMasterChef} from "./interfaces/synapse/IMasterChef.sol";
import {IUniswapV2Router02} from "./interfaces/solidly/IUniswapV2Router02.sol";

contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;

    // tokens
    IERC20 internal constant SYN =
        IERC20(0xE55e19Fb4F2D85af758950957714292DAC1e25B2);

    // lp tokens
    IERC20 internal immutable syn3PoolLP;

    // staking contracts
    IMasterChef internal immutable synStakingMC;

    // pools
    ISwap internal immutable syn3PoolSwap; // Synapse Fantom Stable 3 Pool

    // router
    IUniswapV2Router02 internal immutable solidlyRouter;

    //1	    0.01%
    //5	    0.05%
    //10	0.1%
    //50	0.5%
    //100	1%
    //1000	10%
    //10000	100%
    uint256 public maxSlippageIn; // bips
    uint256 public maxSlippageOut; // bips

    uint256 internal constant ONE_HUNDRED_PERCENT = 10_000; // 100% bips

    uint256 internal immutable pid; // Staking contract Pool ID
    uint8 internal immutable syn3PoolUSDCTokenIndex; // Index of USDC in Synapse Fantom 3 Pool

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
    ) BaseStrategy(_vault) {
        require(
            _maxSlippageIn <= ONE_HUNDRED_PERCENT,
            "maxSlippageIn too high"
        );

        require(
            _maxSlippageOut <= ONE_HUNDRED_PERCENT,
            "maxSlippageOut too high"
        );
        minReportDelay = 7 days;

        syn3PoolLP = IERC20(_synStable3PoolLP); // FTM Mainnet: 0x2DC777ff99058a12844A33D9B1AE6c8AB4701F66
        syn3PoolSwap = ISwap(_synStable3Pool); // FTM Mainnet: 0x85662fd123280827e11C59973Ac9fcBE838dC3B4
        synStakingMC = IMasterChef(_synStakingMC); // FTM Mainnet: 0xaeD5b25BE1c3163c907a471082640450F928DDFE
        solidlyRouter = IUniswapV2Router02(_solidlyRouter); // FTM Mainnet: 0xa38cd27185a464914D3046f0AB9d43356B34829D

        maxSlippageIn = _maxSlippageIn;
        maxSlippageOut = _maxSlippageOut;

        pid = _stakingContractPoolId; // FTM Mainnet: 3
        syn3PoolUSDCTokenIndex = _synStable3PoolUSDCTokenIndex; // FTM Mainnet: 1
    }

    // ******** OVERRIDE THESE METHODS FROM BASE CONTRACT ************

    function name() external pure override returns (string memory) {
        // Add your own name here, suggestion e.g. "StrategyCreamYFI"
        return "StrategySynapseSSSUSDC";
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        return scaledLPtoWant() + wantBalance();
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        // Calim all our SYN tokens and withdraw all of our `nUSD-LP` tokens
        synStakingMC.harvest(pid, address(this));

        uint256 _claimedSYNBalance = claimedSynBalance();
        if (_claimedSYNBalance > 0) {
            // Trade all of our SYN tokens for `want` tokens
            _sellSynToWant(_claimedSYNBalance);
        }

        //grab the estimate total debt from the vault
        uint256 _vaultDebt = vault.strategies(address(this)).totalDebt;
        uint256 _totalAssets = estimatedTotalAssets();

        if (_totalAssets >= _vaultDebt) {
            // Implicitly, _profit & _loss are 0 before we change them.
            _profit = _totalAssets - _vaultDebt;
        } else {
            _loss = _vaultDebt - _totalAssets;
        }

        (uint256 _amountFreed, uint256 _liquidationLoss) = liquidatePosition(
            _debtOutstanding + _profit
        );

        _loss = _loss + _liquidationLoss;

        _debtPayment = Math.min(_debtOutstanding, _amountFreed);

        if (_loss > _profit) {
            _loss = _loss - _profit;
            _profit = 0;
        } else {
            _profit = _profit - _loss;
            _loss = 0;
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        uint256 _looseWant = wantBalance();

        if (_looseWant > _debtOutstanding) {
            uint256 _amountToDeposit = _looseWant - _debtOutstanding;
            _addliquidity(_amountToDeposit);
            _stakeLPTokens(unstakedLPBalance());
        }
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        uint256 _liquidWant = wantBalance();

        _amountNeeded = Math.min(_amountNeeded, estimatedTotalAssets()); // Otherwise we can end up declaring a liquidation loss when _amountNeeded is more than we own

        if (_liquidWant < _amountNeeded) {
            uint256 _lpTokensToSell = scaleWantToLP(_amountNeeded); // How many LP tokens do we need to get the required amount of `want`

            uint256 _stakedLpTokens = stakedLPBalance(); // How many LP tokens do we have staked
            uint256 _unstakedLPTokens = unstakedLPBalance(); // How many are available to unstake?

            // Free up the minimum amount of LP tokens to get to the amount of `want` we need
            if (_unstakedLPTokens < _lpTokensToSell) {
                uint256 _requiredLPTokensToUnstake; // How many more LP tokens do we need to unstake to get the required amount of `want`.
                _requiredLPTokensToUnstake =
                    _lpTokensToSell -
                    _unstakedLPTokens;
                _unstakeLPTokens(
                    Math.min(_stakedLpTokens, _requiredLPTokensToUnstake)
                );
            }

            //withdraw from pool
            uint256 _unstakedLpBalance = unstakedLPBalance();
            if (_unstakedLpBalance > 0) {
                _withdrawLiquidity(
                    _unstakedLpBalance,
                    _minAmountOfLPToWant(_unstakedLpBalance)
                );
            }

            _liquidWant = wantBalance();
        }

        if (_amountNeeded > _liquidWant) {
            _liquidatedAmount = _liquidWant;
            _loss = _amountNeeded - _liquidWant;
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        _unstakeLPTokens(stakedLPBalance());

        uint256 _lpTokenBalance = unstakedLPBalance();
        if (_lpTokenBalance > 0) {
            // Try to withdraw everything in `want`
            _withdrawLiquidity(
                _lpTokenBalance,
                _minAmountOfLPToWant(_lpTokenBalance)
            );
        }

        return wantBalance();
    }

    function emergencyWithdraw() external onlyEmergencyAuthorized {
        synStakingMC.emergencyWithdraw(pid, address(this));
    }

    // NOTE: Can override `tendTrigger` and `harvestTrigger` if necessary

    function prepareMigration(address _newStrategy) internal override {
        SYN.transfer(_newStrategy, claimedSynBalance());

        uint256 _stakedLPBalance = stakedLPBalance();
        if (_stakedLPBalance > 0) {
            synStakingMC.withdraw(pid, _stakedLPBalance, _newStrategy);
        }
        // NOTE: `migrate` will automatically forward all `want` in this strategy to the new one
    }

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {}

    /**
     * @notice
     *  Provide an accurate conversion from `_amtInWei` (denominated in wei)
     *  to `want` (using the native decimal characteristics of `want`).
     * @dev
     *  Care must be taken when working with decimals to assure that the conversion
     *  is compatible. As an example:
     *
     *      given 1e17 wei (0.1 ETH) as input, and want is USDC (6 decimals),
     *      with USDC/ETH = 1800, this should give back 1800000000 (180 USDC)
     *
     * @param _amtInWei The amount (in wei/1e-18 ETH) to convert to `want`
     * @return The amount in `want` of `_amtInEth` converted to `want`
     **/
    function ethToWant(uint256 _amtInWei)
        public
        view
        virtual
        override
        returns (uint256)
    {}

    // ----------------- SUPPORT FUNCTIONS ----------

    /**
     * @notice
     *  Takes the amount in `SYN` and sells it for `want` on solidly
     * @dev
     *  Total amount to sell in wei
     **/
    function _sellSynToWant(uint256 _amount) internal {
        _checkAllowance(address(solidlyRouter), address(SYN), _amount);

        IUniswapV2Router02.route[]
            memory routes = new IUniswapV2Router02.route[](1);
        routes[0].from = address(SYN);
        routes[0].to = address(want);
        routes[0].stable = false;
        uint256[] memory amounts = solidlyRouter.getAmountsOut(_amount, routes);

        if (amounts[1] > 0) {
            solidlyRouter.swapExactTokensForTokensSimple(
                _amount, // amt to sell
                0, // minimnum amount
                address(SYN), // token from
                address(want), // token to
                false, // stable swap
                address(this), // to
                type(uint256).max
            );
        }
    }

    function _addliquidity(uint256 _amount) internal {
        _checkAllowance(address(syn3PoolSwap), address(want), _amount);

        uint256 _expectedLPTokensOut = _calculateAmtWithSlippage(
            scaleWantToLP(_amount),
            maxSlippageIn
        );

        uint256[] memory liquidityToAdd = new uint256[](3);
        liquidityToAdd[1] = _amount; // USDC

        syn3PoolSwap.addLiquidity(
            liquidityToAdd,
            _expectedLPTokensOut,
            type(uint256).max
        );
    }

    function _calculateAmtWithSlippage(uint256 _amount, uint256 _slippage)
        internal
        pure
        returns (uint256)
    {
        uint256 _amtWithSlippage = (_amount *
            (ONE_HUNDRED_PERCENT - _slippage)) / ONE_HUNDRED_PERCENT;
        return _amtWithSlippage;
    }

    function unstakeLPTokens(uint256 _amount) external onlyVaultManagers {
        _unstakeLPTokens(_amount);
    }

    function _unstakeLPTokens(uint256 _amount) internal {
        if (_amount > 0) {
            synStakingMC.withdraw(pid, _amount, address(this));
        }
    }

    function _stakeLPTokens(uint256 _amount) internal {
        _checkAllowance(address(synStakingMC), address(syn3PoolLP), _amount);
        synStakingMC.deposit(pid, _amount, address(this));
    }

    function _minAmountOfLPToWant(uint256 _lpAmount)
        internal
        view
        returns (uint256)
    {
        uint256 _expectedWant = scaleLPToWant(_lpAmount);
        return _calculateAmtWithSlippage(_expectedWant, maxSlippageOut);
    }

    function withdrawLiquidity(uint256 _lpAmount, uint256 _minAmountOfWant)
        external
        onlyVaultManagers
    {
        _withdrawLiquidity(_lpAmount, _minAmountOfWant);
    }

    function _withdrawLiquidity(uint256 _lpAmount, uint256 _minAmountOfWant)
        internal
    {
        _checkAllowance(address(syn3PoolSwap), address(syn3PoolLP), _lpAmount);

        syn3PoolSwap.removeLiquidityOneToken(
            _lpAmount,
            syn3PoolUSDCTokenIndex,
            _minAmountOfWant,
            type(uint256).max
        );
    }

    /**
     * @notice
     *  Takes the total balance of SYN, both claimed and unclaimed and converts and
     *  gets a quote for an equivlant amount of `want` using the Solidly's SYN<>USDC Pool
     * @dev
     *  Total amount includes claimed and unclaimed SYN tokens
     * @return The amount in `want` of `SYN` converted to `want`
     **/
    function synToWantBalance() public view returns (uint256) {
        IUniswapV2Router02.route[]
            memory routes = new IUniswapV2Router02.route[](1);
        routes[0].from = address(SYN);
        routes[0].to = address(want);
        routes[0].stable = false;

        return solidlyRouter.getAmountsOut(claimedSynBalance(), routes)[1];
    }

    /**
     * @notice
     *  Gets the total amount of staked LP token for the stable swap 3 pool
     * @return The amount of `nUSD-LP` that have been staked
     **/
    function stakedLPBalance() public view returns (uint256) {
        (uint256 stakedInMasterchef, ) = synStakingMC.userInfo(
            pid,
            address(this)
        );
        return stakedInMasterchef;
    }

    /**
     * @notice
     *  Total balance of LP tokens that haven't been staked yet
     * @return The amount in `nUSD-LP` that haven't been staked yet
     **/
    function unstakedLPBalance() public view returns (uint256) {
        return syn3PoolLP.balanceOf(address(this));
    }

    /**
     * @notice
     *  The total amount of SYN that hasn't been claimed yet
     * @return The amount in `SYN` that hasn't been claimed yet
     **/
    function unclaimedSynBalance() public view returns (uint256) {
        (, uint256 unclaimedRewards) = synStakingMC.userInfo(
            pid,
            address(this)
        );
        return unclaimedRewards;
    }

    /**
     * @notice
     *  The total amount of SYN that has been claimed
     * @return The amount in `SYN` that has been claimed
     **/
    function claimedSynBalance() public view returns (uint256) {
        return SYN.balanceOf(address(this));
    }

    /**
     * @notice
     *  Total balance of SYN, both claimed and unclaimed
     * @dev
     *  Total amount includes claimed and unclaimed SYN tokens
     * @return The amount in `SYN` of staked and unstaked `SYN` tokens
     **/
    function totalSynBalance() public view returns (uint256) {
        return claimedSynBalance() + unclaimedSynBalance();
    }

    function wantBalance() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    // returns an estimate of want tokens based on lp token balance
    function scaledLPtoWant() public view returns (uint256 _amount) {
        return scaleLPToWant(stakedLPBalance() + unstakedLPBalance());
    }

    function scaleWantToLP(uint256 _amountTokens)
        public
        view
        returns (uint256 _amount)
    {
        uint256 unscaled = (_amountTokens * 1e18) /
            syn3PoolSwap.getVirtualPrice();
        return
            _scaleDecimals(
                unscaled,
                ERC20(address(want)),
                ERC20(address(syn3PoolLP))
            );
    }

    /// use 3pool lp virtual price to estimate equivalent amount of want.
    function scaleLPToWant(uint256 _unscaledAmount)
        public
        view
        returns (uint256 _amount)
    {
        uint256 unscaled = _unscaledAmount *
            (syn3PoolSwap.getVirtualPrice() / 1e18);
        return
            _scaleDecimals(
                unscaled,
                ERC20(address(syn3PoolLP)),
                ERC20(address(want))
            );
    }

    function _scaleDecimals(
        uint256 _amount,
        ERC20 _fromToken,
        ERC20 _toToken
    ) internal view returns (uint256 _scaled) {
        uint256 decFrom = _fromToken.decimals();
        uint256 decTo = _toToken.decimals();
        return
            decTo > decFrom
                ? _amount * (10**(decTo - decFrom))
                : _amount / (10**(decFrom - decTo));
    }

    function setParams(uint256 _maxSlippageIn, uint256 _maxSlippageOut)
        public
        onlyVaultManagers
    {
        require(
            _maxSlippageIn <= ONE_HUNDRED_PERCENT,
            "maxSlippageIn too high"
        );
        maxSlippageIn = _maxSlippageIn;

        require(
            _maxSlippageOut <= ONE_HUNDRED_PERCENT,
            "maxSlippageOut too high"
        );
        maxSlippageOut = _maxSlippageOut;
    }

    function _checkAllowance(
        address _contract,
        address _token,
        uint256 _amount
    ) internal {
        if (IERC20(_token).allowance(address(this), _contract) < _amount) {
            IERC20(_token).safeApprove(_contract, 0);
            IERC20(_token).safeApprove(_contract, _amount);
        }
    }
}
