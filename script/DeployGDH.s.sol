// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {GuardianHulkStableCoin} from "../src/GuardianHulk.sol";
import {GuardianHulkEngine} from "../src/GuardianHulkEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployGDH is Script{
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (GuardianHulkStableCoin,GuardianHulkEngine, HelperConfig){
        HelperConfig config = new HelperConfig();

       (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            config.activeNetworkConfig();
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        GuardianHulkStableCoin gdh = new GuardianHulkStableCoin();
        GuardianHulkEngine engine = new GuardianHulkEngine(tokenAddresses,priceFeedAddresses,address(gdh));

        gdh.transferOwnership(address(engine));
        vm.stopBroadcast();
        return(gdh,engine,config);
    }
}