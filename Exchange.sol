// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

//IMPORTANT: MAKE SURE TO APPROVE THE MAX TOKENS FOR THIS EXCHANGE BEFORE PROVIDING LIQUIDITY
//All output values for ERC20 are the actual tokens. 
//All output values for the ETH is actually in Wei.


contract Exchange{
   //initializing the public variables
   IERC20 ierc20Token;
   uint contractERC20TokenBalance = 0;
   //IMPORTANT: contractEthBalance is actually in Wei
   uint public contractEthBalance = 0;
   uint totalLiquidityPositions = 0;
   uint public K = 0;
   mapping(address => uint) liquidityPositions;
   //contructor to initialize the token address passed in to the public ierc20Token variable
   constructor(address adr){
       address tokenContractAddress = adr;
       ierc20Token = IERC20(tokenContractAddress);
   }
   //modifier to block re-entry of an input so a user cant call the contract in the middle of another call causing issues for withdraws and other operations that could be exploited
   bool locked = false;
   modifier nonReentrancy{
       require (!locked, "No re-entry");
       locked = true;
       _;
       locked = false;
   }
   //event to show the liquidity that is provided to the contract
   event LiquidityProvided(uint amountERC20TokenDeposited, uint amountEthDeposited, uint liquidityPositionsIssued);


   /*
   * Adding the erc20 tokens and eth as liquidity to the contract checking for the same liquidity ratio as the current one
   * Param: uint _amountERC20Token - the amount of erc being provided to the contract
   * Param (external - Value for Eth):  the value being added for the eth with the similar ratio to the erc
   * return: uint _liquidity - returns the amount of liquidity positions issued
   */
   function provideLiquidity(uint _amountERC20Token) external nonReentrancy payable returns(uint _liquidity){

       uint _amountEth = msg.value;
       contractEthBalance += _amountEth;
       //adjusting for erc20 balance
       _amountERC20Token = _amountERC20Token * 1e18;
       ierc20Token.approve(address(this), _amountERC20Token);
       bool success = ierc20Token.transferFrom(msg.sender, address(this), _amountERC20Token);
       require(success, "transfer failed. :(");
       contractERC20TokenBalance += _amountERC20Token;
       require((totalLiquidityPositions * _amountERC20Token/contractERC20TokenBalance) == (totalLiquidityPositions * _amountEth/contractEthBalance), "liquidity inbalance");
           if(totalLiquidityPositions == 0){
               liquidityPositions[msg.sender] = 100;
               totalLiquidityPositions += liquidityPositions[msg.sender];
           }else{
               liquidityPositions[msg.sender] += totalLiquidityPositions * _amountERC20Token / contractERC20TokenBalance;
               totalLiquidityPositions += (totalLiquidityPositions * _amountERC20Token / contractERC20TokenBalance);
           }
       K = contractEthBalance * contractERC20TokenBalance;
       emit LiquidityProvided(_amountERC20Token, _amountEth, liquidityPositions[msg.sender] );
       return liquidityPositions[msg.sender];
   }
   /*
   * Estimating the Ethereum amount to provide based on the current ratio and the amount of erc tokens being passed in
   * Param: uint _amountERC20Token - the amount of erc planned to be added
   * return: uint _amountEth - returns the amount of eth that would need to be added with the passed in erc value to maintain the ratio
   */
   function estimateEthToProvide(uint _amountERC20Token) external view returns (uint _amountEth) {
       //to delete if Korth says that the input will be in 10*18 format
       _amountERC20Token = _amountERC20Token * 1e18;

       _amountEth = contractEthBalance * _amountERC20Token / contractERC20TokenBalance;
       return _amountEth;
   }
   /*
   * Estimating the ERC20 token amount to provide based on the current ratio and the amount of Eth being passed in
   * Param: uint _amountEth - the amount of Eth planned to be added
   * return: uint _amountERC20 - returns the amount of ERC20 that would need to be added with the passed in Eth value to maintain the ratio
   */
   function estimateERC20TokenToProvide(uint _amountEth) external view returns(uint _amountERC20){
       _amountERC20 = contractERC20TokenBalance * _amountEth/contractEthBalance;
       return (_amountERC20/1e18);
   }
   /*
   * Outputs the callers liquidity position based on the address from the mapping
   * return: uint _liquidity - returns the liquidity position of the user calling the function
   */
   function getMyLiquidityPositions() external view returns(uint _liquidity) {
       return liquidityPositions[msg.sender];
   }
   //Event for logging the liquidity that was withdrawn
   event LiquidityWithdrew(uint amountERC20TokenWithdrew, uint amountEthWithdrew, uint liquidityPositionsBurned);
   /*
   * Function to get Eth and ERC20 tokens based on the liquidity positions they are withdrawing
   * Param: uint _liquidityPositionsToBurn - the amount of position you are giving up
   * return: uint amountEthToSend - the Eth amount you are receiving for the liquidity position you give up
   * return: uint amountERC20ToSend - the ERC20 amount you are receiving for the liquidity position you give up
   */
   function withdrawLiquidity(uint _liquidityPositionsToBurn) public nonReentrancy payable returns (uint amountEthToSend, uint amountERC20ToSend){
       if (_liquidityPositionsToBurn <= liquidityPositions[msg.sender] &&  totalLiquidityPositions - _liquidityPositionsToBurn >= 0 ){
           amountEthToSend = _liquidityPositionsToBurn * contractEthBalance / totalLiquidityPositions;
           amountERC20ToSend = _liquidityPositionsToBurn * contractERC20TokenBalance / totalLiquidityPositions;
           liquidityPositions[msg.sender] -= _liquidityPositionsToBurn;
           totalLiquidityPositions -= _liquidityPositionsToBurn;
           address payable reciever = payable(msg.sender);
           reciever.transfer(amountEthToSend);
           contractEthBalance -= amountEthToSend;
           ierc20Token.approve(address(this), amountERC20ToSend);
           ierc20Token.transferFrom(address(this), reciever, amountERC20ToSend);
           contractERC20TokenBalance -= amountERC20ToSend;
       }else{
           amountEthToSend = 0;
           amountERC20ToSend = 0;
       }
       K = contractEthBalance * contractERC20TokenBalance;
       emit LiquidityWithdrew(amountERC20ToSend, amountEthToSend, _liquidityPositionsToBurn);
       return (amountEthToSend, amountERC20ToSend);
   }
   event SwapForEth(uint amountERC20TokenDeposited, uint amountEthWithdrew);
   /*
   * Function to exchange the callers ERC20 tokens for Eth using the K value for appropriate ratios
   * Param: uint _amountERC20Token - the amount of ERC20 tokens a person is giving up
   * return: uint ethToSend - The amount of Eth being sent based on the ERC20 Token amount passed in
   */
   function swapForEth(uint _amountERC20Token) public nonReentrancy payable returns (uint ethToSend) {
       //to delete if Korth says that the input will be in 10*18 format
       _amountERC20Token = _amountERC20Token * 1e18;
       ierc20Token.transferFrom(msg.sender, address(this), _amountERC20Token);
       contractERC20TokenBalance += _amountERC20Token;
       uint contractEthBalanceAfterSwap = K / contractERC20TokenBalance;
       ethToSend = contractEthBalance - contractEthBalanceAfterSwap;
       address payable reciever = payable(msg.sender);
       reciever.transfer(ethToSend);
       contractEthBalance -= ethToSend;
       emit SwapForEth(_amountERC20Token, ethToSend);
       return ethToSend;
   }
   /*
   * Function to show how much a person would receive in Eth for the amount of ERC20 tokens they pass in
   * Param: uint _amountERC20Token - the amount of ERC20 tokens a person is testing to give up
   * return: uint ethToSend - The amount of Eth shown to be sent back based on the ERC20 Token amount passed in
   */
   function estimateSwapForEth(uint _amountERC20Token) external view returns (uint ethToSend){
       //to delete if Korth says that the input will be in 10*18 format
       _amountERC20Token = _amountERC20Token * 1e18;
       
       uint estimatedContractERC20Balance = contractERC20TokenBalance + _amountERC20Token;
       uint contractETHBalanceAfterSwap = K / estimatedContractERC20Balance;
       ethToSend = contractEthBalance - contractETHBalanceAfterSwap;
       return ethToSend;
   }
   event SwapForERC20Token(uint amountERC20TokenWithdrew, uint amountEthDeposited);


   /*
   * Function to exchange the callers Eth for ERC20 tokens using the K value for appropriate ratios
   * Param (external - Value for Eth):  the value being added for the Eth that will be exchanged for ERC20 Tokens
   * return: uint ERC20TokenToSend - The amount of ERC20 Tokens being sent based on the Eth amount passed in
   */
   function swapForERC20Token() external nonReentrancy payable returns (uint ERC20TokenToSend){
       contractEthBalance += msg.value;
       uint contractERC20TokenBalanceAfterSwap = K / contractEthBalance;
       ERC20TokenToSend = contractERC20TokenBalance - contractERC20TokenBalanceAfterSwap;
       address payable reciever = payable(msg.sender);
       ierc20Token.approve(address(this), ERC20TokenToSend);
       ierc20Token.transferFrom(address(this), reciever, ERC20TokenToSend);
       contractERC20TokenBalance = contractERC20TokenBalanceAfterSwap;
       emit SwapForERC20Token(ERC20TokenToSend,msg.value);
       return ERC20TokenToSend;
   }
   /*
   * Function to show how much a person would receive in ERC20 Tokens for the amount of Eth they pass in
   * Param: uint _amountEth - the amount of Eth a person is testing to give up
   * return: uint ERC20TokenToSend - The amount of ERC20 Tokens shown to be sent back based on the Eth amount passed in
   */
   function estimateSwapForERC20Token(uint _amountEth) external view returns (uint ERC20TokenToSend){
       uint estimatedContractEthBalance = contractEthBalance + _amountEth;
       uint contractERC20TokenBalanceAfterSwap = K / estimatedContractEthBalance;
       ERC20TokenToSend = contractERC20TokenBalance - contractERC20TokenBalanceAfterSwap;
       return (ERC20TokenToSend/1e19);
   }
   /*
   * Outputs the balance of the ERC20 Tokens for that address instance
   * return: uint - The amount of ERC20 Tokens of the balance in that instance from where it is called
   */
   function _ERC20TokenBalance() external view returns (uint) {
       return (ierc20Token.balanceOf(address(this))/1e18);
   }
}



