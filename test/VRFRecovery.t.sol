
 // SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {
    VRFCoordinatorV2_5Mock
} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

import {BMCIlluminatiPass} from "../src/BMCIlluminatiPass.sol";
import {MockBMC} from "./mocks/MockBMC.sol";

contract VRFRecoveryTest is Test {
    MockBMC bmc;
    VRFCoordinatorV2_5Mock coordinator;
    BMCIlluminatiPass pass;

    uint256 subId;

    address owner = makeAddr("owner");
    address subOwner = makeAddr("subscriptionOwner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        bmc = new MockBMC();

        coordinator = new VRFCoordinatorV2_5Mock(
            0.1 ether,
            1e9,
            4e15
        );

        pass = new BMCIlluminatiPass(
            owner,
            address(bmc),
            address(coordinator)
        );

        vm.startPrank(subOwner);
        subId = coordinator.createSubscription();
        coordinator.addConsumer(subId, address(pass));
        vm.stopPrank();

        vm.startPrank(owner);
        pass.setGenesisImagesCID("bafysecuritytest");
        pass.setVRFConfig(
            subId,
            keccak256("lane"),
            500_000,
            3,
            false
        );
        vm.stopPrank();

        coordinator.fundSubscription(subId, 100 ether);

        for (uint256 i = 0; i < 40; i++) {
            address who = address(uint160(0x7000 + i));

            bmc.mint(who, 1_000_000e18);

            vm.startPrank(who);
            bmc.approve(address(pass), 1_000_000e18);
            pass.mintGenesis();
            vm.stopPrank();
        }
    }

    function _mintMystery(address who)
        internal
        returns (uint256 id, uint256 requestId)
    {
        bmc.mint(who, 350_000e18);

        vm.startPrank(who);
        bmc.approve(address(pass), 350_000e18);
        (id, requestId) = pass.mintMystery();
        vm.stopPrank();
    }

    function testMissingEarlierRequestBlocksLaterReveal()
        public
    {
        (uint256 id41, uint256 request41) =
            _mintMystery(alice);

        (uint256 id42, uint256 request42) =
            _mintMystery(bob);

        assertEq(id41, 41);
        assertEq(id42, 42);

        // Request #41 is deliberately never fulfilled.
        // This simulates a permanently unavailable request.
        assertGt(request41, 0);

        uint256[] memory words = new uint256[](1);
        words[0] = 424242;

        coordinator.fulfillRandomWordsWithOverride(
            request42,
            address(pass),
            words
        );

        assertEq(
            uint8(pass.revealStatusOf(42)),
            uint8(
                BMCIlluminatiPass.RevealStatus.RandomnessStored
            )
        );

        assertEq(
            uint8(pass.tierOf(42)),
            uint8(BMCIlluminatiPass.Tier.Pending)
        );

        assertEq(pass.artworkIdOf(42), 0);

        // The earlier missing request blocks finalization.
        assertEq(pass.finalizeReveals(10), 0);

        vm.warp(block.timestamp + 200 days);
        vm.roll(block.number + 1);

        // Waiting alone cannot unblock the reveal.
        assertEq(pass.finalizeReveals(10), 0);

        assertEq(
            uint8(pass.tierOf(42)),
            uint8(BMCIlluminatiPass.Tier.Pending)
        );

        assertEq(pass.pendingReveals(), 2);
    }
}
