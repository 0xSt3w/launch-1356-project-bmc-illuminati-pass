// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {BMCIlluminatiPass} from "../src/BMCIlluminatiPass.sol";
import {MockBMC} from "./mocks/MockBMC.sol";

/// @notice Additional regression tests for the existing strict-order VRF design.
/// @dev These document current behavior; they do NOT fix lost/expired requests.
contract VRFRecoveryAdditionalTest is Test {
    MockBMC bmc;
    VRFCoordinatorV2_5Mock coordinator;
    BMCIlluminatiPass pass;
    uint256 subId;
    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        bmc = new MockBMC();
        coordinator = new VRFCoordinatorV2_5Mock(0.1 ether, 1e9, 4e15);
        pass = new BMCIlluminatiPass(owner, address(bmc), address(coordinator));
        subId = coordinator.createSubscription();
        coordinator.addConsumer(subId, address(pass));
        coordinator.fundSubscription(subId, 100 ether);
        vm.startPrank(owner);
        pass.setGenesisImagesCID("bafyregression");
        pass.setVRFConfig(subId, keccak256("lane"), 500_000, 3, false);
        vm.stopPrank();
        for (uint256 i = 0; i < 40; ++i) {
            address minter = address(uint160(0x7000 + i));
            bmc.mint(minter, 1_000_000e18);
            vm.startPrank(minter);
            bmc.approve(address(pass), 1_000_000e18);
            pass.mintGenesis();
            vm.stopPrank();
        }
    }

    function _mint(address minter) internal returns (uint256 id, uint256 req) {
        bmc.mint(minter, 350_000e18);
        vm.startPrank(minter);
        bmc.approve(address(pass), 350_000e18);
        (id, req) = pass.mintMystery();
        vm.stopPrank();
    }

    function testLaterRandomnessStoredUntilEarlierRequestArrives() public {
        (uint256 id41, uint256 req41) = _mint(alice);
        (uint256 id42, uint256 req42) = _mint(bob);
        assertEq(id41, 41);
        assertEq(id42, 42);

        uint256[] memory words = new uint256[](1);
        words[0] = 42;
        coordinator.fulfillRandomWordsWithOverride(req42, address(pass), words);
        assertEq(uint8(pass.revealStatusOf(id42)), uint8(BMCIlluminatiPass.RevealStatus.RandomnessStored));
        assertEq(pass.finalizeReveals(10), 0);
        assertEq(pass.artworkIdOf(id42), 0);

        words[0] = 41;
        coordinator.fulfillRandomWordsWithOverride(req41, address(pass), words);
        // Depending on callback gas, permissionless finalization finishes any stored words.
        pass.finalizeReveals(10);
        assertEq(uint8(pass.revealStatusOf(id41)), uint8(BMCIlluminatiPass.RevealStatus.Revealed));
        assertEq(uint8(pass.revealStatusOf(id42)), uint8(BMCIlluminatiPass.RevealStatus.Revealed));
        assertEq(pass.revealedCount(), 2);
        assertEq(pass.pendingReveals(), 0);
        assertTrue(pass.artworkIdOf(id41) != 0);
        assertTrue(pass.artworkIdOf(id42) != 0);
    }
}
