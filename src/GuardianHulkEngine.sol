// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {GuardianHulkStableCoin} from "./GuardianHulk.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/*
* @title GuardianHulkEngine
* @author HulkOfKnowledge
* This system is designed to have the tokens maintain a 1 token = $1 peg
* 
* The coin has the following properties:
* Collateral: Exogenous (ETH & BTC)
* Minting: Algorithmic
* Relative Stability: Pegged to USD
* 
* It is similar to DAI if DAI had no governance, no fees and was only backed by
WETH and WBTC.
*
* Our GuardianHulk System should always be "overcollateralized". At no point should the 
Value of all collateral <= the dollar backed value of all the GuardianHulk StableCoin
*
*
* @notice This contract handles all the logic of the GuardianHulK stablecoin.
*/
contract GuardianHulkEngine is ReentrancyGuard{
    //Errors
    error GuardianHulkEngine__zeroAmount();
    error GuardianHulkEngine__tokenNotAllowed();
    error GuardianHulkEngine__transferFailed();
    error GuardianHulkEngine__LengthMismatch_TokenAddressesAndPriceAddresses();
    error GuardianHulkEngine__badHealthFactor(uint256 healthFactor);
    error GuardianHulkEngine__MintFailed();

    // State Variables
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    mapping(address token => address priceFeed) private s_priceFeeds; //tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountMinted) private s_GDHMinted;
    address[] private s_collateralTokens;

    GuardianHulkStableCoin private immutable i_GDH;

    //Events
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed  amount);
    event GDHMinted(address indexed user, uint256 indexed amount);
    event CollateralRedeemed(address indexed user, address indexed token, uint256 indexed amount);

    // Modifiers
    modifier validAmount(uint256 amount){
        if (amount == 0){
            revert GuardianHulkEngine__zeroAmount();
        }
        _;
    }

    modifier validToken(address token){
        if(s_priceFeeds[token] == address(0)){
            revert GuardianHulkEngine__tokenNotAllowed();
        }
        _;
    }

    // Functions

    constructor(
        address[] memory tokenAddresses, 
        address[] memory priceFeedAddresses,
        address GDHaddress
        ){
            if (tokenAddresses.length !=priceFeedAddresses.length){
                revert GuardianHulkEngine__LengthMismatch_TokenAddressesAndPriceAddresses();
            }
            
            // USD price feeds
            // Example ETH/USD. BTC/USD
            for(uint256 i=0;i<tokenAddresses.length;i++){
                s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
                s_collateralTokens.push(tokenAddresses[i]);
            }
            i_GDH = GuardianHulkStableCoin(GDHaddress);
        }

    // External Functions


    /*
     * @param tokenCollateralAddress -> The address of the token to deposit as collateral
     * @param amountCollateral -> The amount of collateral to deposit
     * @param amountToMint -> The amount of GDH to mint
     * @notice the function will deposit the collateral and mint the GDH
     * @notice they must have more collateral value than the minimum threshold

    */
    function depositCollateralAndMintGDH(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountToMint
    ) external {
        depositCollateral(tokenCollateralAddress,amountCollateral);
        mintGDH(amountToMint);
    }
   


    /*
     * @notice follows CEI
     * @param tokenCollateralAddress -> The address of the token to deposit as collateral
     * @param amountCollateral -> The amount of collateral to deposit
    
    */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
     ) 
     public 
     validAmount(amountCollateral)
     validToken(tokenCollateralAddress)
     nonReentrant
     {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender,tokenCollateralAddress,amountCollateral);
        bool success= IERC20(tokenCollateralAddress).transferFrom(msg.sender,address(this),amountCollateral);
        if(!success){
            revert GuardianHulkEngine__transferFailed();
        }
     }

    /*
     * @param tokenCollateralAddress -> The address of the token to redeem as collateral
     * @param amountCollateral -> The amount of collateral to redeem
     * @param amountToBurn -> The amount of GDH to burn
     * @notice the function will redeem the collateral and burn the GDH in one transaction
    */
    function redeemCollateralforGDH(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountToBurn
    ) external {
        burnGDH(amountToBurn);
        redeemCollateral(tokenCollateralAddress,amountCollateral);
    }

    // In order to redeem collateral, they must have  a health factor > 1 after collateral is removed
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public
    validAmount(amountCollateral)
    validToken(tokenCollateralAddress)
    nonReentrant
     {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(msg.sender,tokenCollateralAddress,amountCollateral);
        bool success= IERC20(tokenCollateralAddress).transfer(msg.sender,amountCollateral);
        if(!success){
            revert GuardianHulkEngine__transferFailed();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     * @notice follows CEI
     * @param amountToMint -> The amount of GDH to mint
     * @notice they must have more collateral value than the minimum threshold
    */
    function mintGDH(uint256 amountToMint)
    public
    validAmount(amountToMint)
    nonReentrant {
        s_GDHMinted[msg.sender] += amountToMint;
        // If they minted too much ($150GDH, $100ETH)
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_GDH.mint(msg.sender,amountToMint);
        if(!minted){
            revert GuardianHulkEngine__MintFailed();
        }
    }

    function burnGDH(uint256 amount) 
    external
    validAmount(amount)
     {
        s_GDHMinted[msg.sender] -= amount;
        bool success = i_GDH.transferFrom(msg.sender,address(this),amount);
        if(!success){
            revert GuardianHulkEngine__transferFailed();
        }
        i_GDH.burn(amount);
        _revertIfHealthFactorIsBroken(msg.sender);
     }

    /*
    * @param collateral -> The ERC20 collateral address to liquidate from 
    * @param user -> User to liquidate
    * @param debtToCover -> The amount of debt to cover 
    */
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external
     {}

    function getHealthFactor() external view {}

    // Private and Internal view Functions

    function _getAccountInfo(address user) private view 
    returns(uint256 totalGDHminted, uint256 collateralValueInUsd){
        totalGDHminted = s_GDHMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }
      
    /*
     * Returns how close to liquidation a user is
     * If a user goes below 1, then they can get liquidated
    */
    function _healthFactor(address user) private view returns(uint256){
        (uint256 totalGDHMinted, uint256 collateralValueInUsd)= _getAccountInfo(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd*LIQUIDATION_THRESHOLD)/LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalGDHMinted;
    }

    // 1. If the health factor is below MIN_HEALTH_FACTOR, then revert
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR){
            revert GuardianHulkEngine__badHealthFactor(userHealthFactor);
        }

    }

    // public and external view functions
    function getAccountCollateralValue(address user) public view 
    returns(uint256 totalCollateralValueInUsd){
        for (uint256 i =0; i<s_collateralTokens.length;i++){
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token,amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns(uint256){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price)* ADDITIONAL_FEED_PRECISION)*amount)/PRECISION;
    }
}