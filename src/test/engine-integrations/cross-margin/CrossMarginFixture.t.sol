// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "../../mocks/MockERC20.sol";
import "../../mocks/MockOracle.sol";
import "../../mocks/MockWhitelist.sol";
import "../../mocks/MockChainlinkAggregator.sol";

import "../../../core/engines/cross-margin/CrossMarginEngine.sol";
import "../../../core/engines/cross-margin/CrossMarginEngineProxy.sol";
import "../../../core/Grappa.sol";
import "../../../core/GrappaProxy.sol";
import "../../../core/OptionToken.sol";

import "../../../config/enums.sol";
import "../../../config/types.sol";

import "../../utils/Utilities.sol";

import {ActionHelper} from "../../shared/ActionHelper.sol";

// solhint-disable max-states-count

/**
 * helper contract for full margin integration test to inherit.
 */
abstract contract CrossMarginFixture is Test, ActionHelper, Utilities {
    CrossMarginEngine internal engine;
    Grappa internal grappa;
    OptionToken internal option;

    MockERC20 internal usdc;
    MockERC20 internal weth;

    MockOracle internal oracle;

    MockWhitelist internal whitelist;

    address internal alice;
    address internal charlie;
    address internal bob;

    // usdc collateralized call / put
    uint40 internal pidUsdcCollat;

    // eth collateralized call / put
    uint40 internal pidEthCollat;

    uint8 internal usdcId;
    uint8 internal wethId;

    uint8 internal engineId;
    uint8 internal oracleId;

    constructor() {
        usdc = new MockERC20("USDC", "USDC", 6); // nonce: 1

        weth = new MockERC20("WETH", "WETH", 18); // nonce: 2

        oracle = new MockOracle(); // nonce: 3

        // predit address of margin account and use it here
        address grappaAddr = predictAddress(address(this), 6);

        option = new OptionToken(grappaAddr, address(0)); // nonce: 4

        address grappaImplementation = address(new Grappa(address(option))); // nonce: 5

        bytes memory grappaData = abi.encode(Grappa.initialize.selector);

        grappa = Grappa(address(new GrappaProxy(grappaImplementation, grappaData))); // 6

        address engineImplementation = address(new CrossMarginEngine(address(grappa), address(option))); // nonce 7

        bytes memory engineData = abi.encode(CrossMarginEngine.initialize.selector);

        engine = CrossMarginEngine(address(new CrossMarginEngineProxy(engineImplementation, engineData))); // 8

        whitelist = new MockWhitelist();

        // register products
        usdcId = grappa.registerAsset(address(usdc));
        wethId = grappa.registerAsset(address(weth));

        engineId = grappa.registerEngine(address(engine));

        oracleId = grappa.registerOracle(address(oracle));

        pidUsdcCollat = grappa.getProductId(address(oracle), address(engine), address(weth), address(usdc), address(usdc));
        pidEthCollat = grappa.getProductId(address(oracle), address(engine), address(weth), address(usdc), address(weth));

        charlie = address(0xcccc);
        vm.label(charlie, "Charlie");

        bob = address(0xb00b);
        vm.label(bob, "Bob");

        alice = address(0xaaaa);
        vm.label(alice, "Alice");

        // make sure timestamp is not 0
        vm.warp(0xffff);

        usdc.mint(alice, 1000_000_000 * 1e6);
        usdc.mint(bob, 1000_000_000 * 1e6);
        usdc.mint(charlie, 1000_000_000 * 1e6);
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external virtual returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function mintOptionFor(address _recipient, uint256 _tokenId, uint40 _productId, uint256 _amount) internal {
        address anon = address(0x42424242);

        vm.startPrank(anon);

        uint256 lotOfCollateral = 1_000 * 1e18;

        usdc.mint(anon, lotOfCollateral);
        weth.mint(anon, lotOfCollateral);
        usdc.approve(address(engine), type(uint256).max);
        weth.approve(address(engine), type(uint256).max);

        ActionArgs[] memory actions = new ActionArgs[](2);

        uint8 collateralId = uint8(_productId);

        actions[0] = createAddCollateralAction(collateralId, address(anon), lotOfCollateral);
        actions[1] = createMintAction(_tokenId, address(_recipient), _amount);
        engine.execute(address(anon), actions);

        vm.stopPrank();
    }

    // place holder here so forge coverage won't pick it up
    function test() public {}
}
