// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployGDH} from "../../script/DeployGDH.s.sol";
import {GuardianHulkStableCoin} from "../../src/GuardianHulk.sol";
import {GuardianHulkEngine} from "../../src/GuardianHulkEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract GuardianHulkEngineTest is Test {
    DeployGDH deployer;
    GuardianHulkStableCoin gdh;
    GuardianHulkEngine engine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployGDH();
        (gdh, engine,config) = deployer.run();
        (ethUsdPriceFeed,,weth,,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER,STARTING_ERC20_BALANCE);
    }

    //////////////////////////
    // Price Tests
    //////////////////////////

    function testGetUsdValue() public{
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 24376e18;
        uint256 actualUsdValue = engine.getUsdValue(weth,ethAmount); 
        assertEq(expectedUsd,actualUsdValue);
    }

    //////////////////////////
    // DepositCollateral Tests
    //////////////////////////

    function testRevertsifCollateralZero() public{
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine),AMOUNT_COLLATERAL);
        vm.expectRevert(GuardianHulkEngine.GuardianHulkEngine__zeroAmount.selector);
        engine.depositCollateral(weth,0);
        vm.stopPrank();
    }

}