// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;


import '../interfaces/Uniswapv3/ISwapRouter.sol';
import "../interfaces/AAVE/FlashLoanReceiverBase.sol";
import "../CErc20.sol";
import "hardhat/console.sol";

contract TestAaveFlashLoan is FlashLoanReceiverBase {
  using SafeMath for uint;

  ISwapRouter public immutable swapRouter;
  CErc20 public immutable cErc20;
  // Uniswap
  address public constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
  address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  uint24 public constant poolFee = 3000;

  event Log(string message, uint val);

  constructor(ILendingPoolAddressesProvider _addressProvider,ISwapRouter _swapRouter,CErc20 _CtokenAddress)
    FlashLoanReceiverBase(_addressProvider)
  {
    swapRouter = ISwapRouter(_swapRouter);
    cErc20 = CErc20(_CtokenAddress);
  }
  
  ///@param asset ERC20 token address
  ///@param amount loan amount
  function testFlashLoan(address asset, uint amount) external {
    uint bal = IERC20(asset).balanceOf(address(this));
    require(bal > amount, "bal <= amount");
    address receiver = address(this);

    address[] memory assets = new address[](1);
    assets[0] = asset;

    uint[] memory amounts = new uint[](1);
    amounts[0] = amount;

    // 0 = no debt, 1 = stable, 2 = variable
    // 0 = pay all loaned
    uint[] memory modes = new uint[](1);
    modes[0] = 0;

    address onBehalfOf = address(this);

    bytes memory params = ""; // extra data to pass abi.encode(...)
    uint16 referralCode = 0;

    LENDING_POOL.flashLoan(
      receiver,
      assets,
      amounts,
      modes,
      onBehalfOf,
      params,
      referralCode
    );
  }

  function executeOperation(
    address[] calldata assets,
    uint[] calldata amounts,
    uint[] calldata premiums,
    address initiator,
    bytes calldata params
  ) external override returns (bool) {
      // approve this address for uniswap using USDC
      IERC20(assets[0]).approve(address(swapRouter),amounts[0]);
      
      // exchange from USDC to UNI
      ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: USDC,
                tokenOut: UNI,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amounts[0],
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
      uint amountOut_UNI = swapRouter.exactInputSingle(params);
    
      // approve this address for uniswap using UNI
      IERC20(UNI).approve(address(swapRouter),amountOut_UNI);
      
      // exchange from UNI to USDC
      ISwapRouter.ExactInputSingleParams memory params_UNI =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: UNI,
                tokenOut: USDC,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountOut_UNI,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
  
      uint amountOut_USDC = swapRouter.exactInputSingle(params_UNI);

    for (uint i = 0; i < assets.length; i++) {
      //歸還數量需要加上手續費，AAVE手續費為萬分之9
      uint amountOwing = amounts[i].add(premiums[i]);
      IERC20(assets[i]).approve(address(LENDING_POOL), amountOwing);
    }

    return true;
  }
}
