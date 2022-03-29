// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;
pragma abicoder v2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ExtendedDSTest} from "./ExtendedDSTest.sol";
import {stdCheats} from "forge-std/stdlib.sol";
import {Vm} from "forge-std/Vm.sol";
import {IVault} from "../../interfaces/Vault.sol";
import {IUniswapV2Router02} from "../../interfaces/solidly/IUniswapV2Router02.sol";

// NOTE: if the name of the strat or file changes this needs to be updated
import {Strategy} from "../../Strategy.sol";

// Artifact paths for deploying from the deps folder, assumes that the command is run from
// the project root.
string constant vaultArtifact = "artifacts/Vault.json";

// Base fixture deploying Vault
contract StrategyFixture is ExtendedDSTest, stdCheats {
    using SafeERC20 for IERC20;

    //Setup some addresses for contracts the strategy will interact with
    address public syn3PoolSwap = 0x85662fd123280827e11C59973Ac9fcBE838dC3B4;
    address public synStakingMC = 0xaeD5b25BE1c3163c907a471082640450F928DDFE;
    address public solidlyRouter = 0xa38cd27185a464914D3046f0AB9d43356B34829D;

    uint256 public pid = 3;
    uint8 public syn3PoolUSDCTokenIndex = 1;

    // we use custom names that are unlikely to cause collisions so this contract
    // can be inherited easily
    // TODO: see if theres a better way to use this
    Vm public constant vm_std_cheats =
        Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    IVault public vault;
    Strategy public strategy;
    IERC20 public weth;
    IERC20 public want;

    mapping(string => address) tokenAddrs;

    address public gov = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52;
    address public user = address(1);
    address public whale = address(2);
    address public rewards = address(3);
    address public guardian = address(4);
    address public management = address(5);
    address public strategist = address(6);
    address public keeper = address(7);

    address public swapLPUser = address(8);

    uint256 public constant ONE_PERCENT = 10_000;
    uint256 public SLIPPAGE_IN;
    uint256 public SLIPPAGE_OUT;

    // Convinence method
    uint256 public constant ONE_USDC = 1e6 wei;

    // Used for integer approximation
    uint256 public constant DELTA = 10**3;

    function setUp() public virtual {
        _setTokenAddrs();

        // Choose a token from the tokenAddrs mapping, see _setTokenAddrs for options
        want = IERC20(tokenAddrs["USDC"]);

        deployVaultAndStrategy(
            address(want),
            gov,
            rewards,
            "",
            "",
            guardian,
            management,
            keeper,
            strategist
        );

        // add more labels to make your traces readable
        vm_std_cheats.label(address(vault), "Vault");
        vm_std_cheats.label(address(strategy), "Strategy");
        vm_std_cheats.label(address(want), "Want");
        vm_std_cheats.label(gov, "Gov");
        vm_std_cheats.label(user, "User");
        vm_std_cheats.label(whale, "Whale");
        vm_std_cheats.label(rewards, "Rewards");
        vm_std_cheats.label(guardian, "Guardian");
        vm_std_cheats.label(management, "Management");
        vm_std_cheats.label(strategist, "Strategist");
        vm_std_cheats.label(keeper, "Keeper");
        vm_std_cheats.label(address(weth), "WETH");
        vm_std_cheats.label(address(want), "USDC");
        vm_std_cheats.label(syn3PoolSwap, "Synapse Stable 3 Pool");
        vm_std_cheats.label(synStakingMC, "Synapse Staking Master Chef");
        vm_std_cheats.label(solidlyRouter, "Solidly SYN<>USDC Pool");

        SLIPPAGE_IN = 5;
        SLIPPAGE_OUT = 5;

        // do here additional setup
        vm_std_cheats.prank(gov);
        vault.setDepositLimit(type(uint256).max);
    }

    // Deploys a vault
    function deployVault(
        address _token,
        address _gov,
        address _rewards,
        string memory _name,
        string memory _symbol,
        address _guardian,
        address _management
    ) public returns (address) {
        vm_std_cheats.prank(gov);
        address _vault = deployCode(vaultArtifact);
        vault = IVault(_vault);

        vm_std_cheats.prank(gov);
        vault.initialize(
            _token,
            _gov,
            _rewards,
            _name,
            _symbol,
            _guardian,
            _management
        );

        return address(vault);
    }

    // Deploys a strategy
    function deployStrategy(address _vault) public returns (address) {
        Strategy _strategy = new Strategy(
            _vault,
            tokenAddrs["SYN3PoolLP"],
            syn3PoolSwap,
            solidlyRouter,
            synStakingMC,
            pid,
            syn3PoolUSDCTokenIndex,
            5000,
            5000
        );

        return address(_strategy);
    }

    // Deploys a vault and strategy attached to vault
    function deployVaultAndStrategy(
        address _token,
        address _gov,
        address _rewards,
        string memory _name,
        string memory _symbol,
        address _guardian,
        address _management,
        address _keeper,
        address _strategist
    ) public returns (address _vault, address _strategy) {
        vm_std_cheats.prank(gov);
        _vault = deployCode(vaultArtifact);
        vault = IVault(_vault);

        vm_std_cheats.prank(gov);
        vault.initialize(
            _token,
            _gov,
            _rewards,
            _name,
            _symbol,
            _guardian,
            _management
        );

        vm_std_cheats.prank(_strategist);
        _strategy = deployStrategy(_vault);
        strategy = Strategy(_strategy);

        vm_std_cheats.prank(_strategist);
        strategy.setKeeper(_keeper);

        vm_std_cheats.prank(gov);
        vault.addStrategy(_strategy, 10_000, 0, type(uint256).max, 1_000);
    }

    function _setTokenAddrs() internal {
        tokenAddrs["WBTC"] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        tokenAddrs["YFI"] = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
        tokenAddrs["WETH"] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        tokenAddrs["LINK"] = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        tokenAddrs["USDT"] = 0x049d68029688eAbF473097a2fC38ef61633A3C7A;
        tokenAddrs["DAI"] = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        tokenAddrs["USDC"] = 0x04068DA6C83AFCFA0e13ba15A6696662335D5B75;
        tokenAddrs["SYN3PoolLP"] = 0x2DC777ff99058a12844A33D9B1AE6c8AB4701F66;
        tokenAddrs["SYN"] = 0xE55e19Fb4F2D85af758950957714292DAC1e25B2;
        tokenAddrs["NUSD"] = 0xED2a7edd7413021d440b09D654f3b87712abAB66;
    }
}
