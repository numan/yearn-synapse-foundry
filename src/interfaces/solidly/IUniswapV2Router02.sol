// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;

pragma experimental ABIEncoderV2;


interface IUniswapV2Router02 {
    struct route {
        address from;
        address to;
        bool stable;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactTokensForTokensSimple(
        uint amountIn,
        uint amountOutMin,
        address tokenFrom,
        address tokenTo,
        bool stable,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function getAmountsOut(
        uint amountIn,
        route[] memory routes) external view returns (uint[] memory amounts);

    function pairFor(
        address tokenA,
        address tokenB,
        bool stable) external view returns (address pair);
}