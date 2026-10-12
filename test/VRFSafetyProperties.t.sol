// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {BMCIlluminatiPass} from "../src/BMCIlluminatiPass.sol";
import {MockBMC} from "./mocks/MockBMC.sol";

/// @notice Regression tests for existing VRF safety properties; NOT an expiry recovery fix.
contract VRFSafetyPropertiesTest is Test {
    MockBMC internal bmc;
    VRFCoordinatorV2_5Mock internal coordinator;
    BMCIlluminatiPass internal pass;
    uint256 internal subId;
    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        bmc = new MockBMC();
        coordinator = new VRFCoordinatorV2_5Mock(0.1 ether, 1e9, 4e15);
        pass = new BMCIlluminatiPass(owner, address(bmc), address(coordinator));
        subId = coordinator.createSubscription();
        coordinator.addConsumer(subId, address(pass));
        coordinator.fundSubscription(subId, 100 ether);
        vm.startPrank(owner);
        pass.setGenesisImagesCID("bafysecuritytests");
        pass.setVRFConfig(subId, keccak256("lane"), 500_000, 3, false);
        vm.stopPrank();
        for (uint256 i = 0; i < 40; ++i) {
            address minter = address(uint160(0x7000 + i));
            bmc.mint(minter, 1_000_000 ether);
            vm.startPrank(minter);
            bmc.approve(address(pass), 1_000_000 ether);
            pass.mintGenesis();
            vm.stopPrank();
        }
    }

    function _mintMystery(address who) internal returns (uint256 id, uint256 requestId) {
        bmc.mint(who, 350_000 ether);
        vm.startPrank(who);
        bmc.approve(address(pass), 350_000 ether);
        (id, requestId) = pass.mintMystery();
        vm.stopPrank();
    }

    function testOnlyCoordinatorMayDeliverRandomness() public {
        (uint256 id, uint256 requestId) = _mintMystery(alice);
        uint256[] memory words = new uint256[](1);
        words[0] = 123;
        vm.prank(alice);
        vm.expectRevert(BMCIlluminatiPass.OnlyCoordinator.selector);
        pass.rawFulfillRandomWords(requestId, words);
        assertEq(uint8(pass.revealStatusOf(id)), uint8(BMCIlluminatiPass.RevealStatus.AwaitingRandomness));
    }

    function testDelayedPredecessorDoesNotBurnAgainOrChangeSupply() public {
        (uint256 id41, uint256 req41) = _mintMystery(alice);
        (uint256 id42, uint256 req42) = _mintMystery(bob);
        uint256 minted = pass.totalMinted();
        uint256 burned = pass.totalBurned();
        uint256[] memory words = new uint256[](1);
        words[0] = 4242;
        coordinator.fulfillRandomWordsWithOverride(req42, address(pass), words);
        assertEq(uint8(pass.revealStatusOf(id42)), uint8(BMCIlluminatiPass.RevealStatus.RandomnessStored));
        assertEq(pass.finalizeReveals(10), 0);
        vm.warp(block.timestamp + 200 days);
        assertEq(pass.finalizeReveals(10), 0);
        assertEq(pass.totalMinted(), minted);
        assertEq(pass.totalBurned(), burned);
        words[0] = 41;
        coordinator.fulfillRandomWordsWithOverride(req41, address(pass), words);
        assertEq(uint8(pass.revealStatusOf(id41)), uint8(BMCIlluminatiPass.RevealStatus.Revealed));
        assertEq(uint8(pass.revealStatusOf(id42)), uint8(BMCIlluminatiPass.RevealStatus.Revealed));
        assertEq(pass.totalMinted(), minted);
        assertEq(pass.totalBurned(), burned);
        assertEq(pass.revealedCount(), 2);
    }
}
