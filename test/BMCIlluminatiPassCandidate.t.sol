// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {BMCIlluminatiPassCandidate} from "../src/experimental/BMCIlluminatiPassCandidate.sol";
import {MockBMC} from "./mocks/MockBMC.sol";
import {MockVRFCoordinator} from "./mocks/MockVRFCoordinator.sol";

contract RegisteredCoordinator is MockVRFCoordinator {
    bytes32 public constant VALID_KEY = keccak256("registered-key");
    function s_provingKeys(bytes32 key) external pure returns (bool exists, uint64 maxGas) {
        return (key == VALID_KEY, key == VALID_KEY ? uint64(500 gwei) : uint64(0));
    }
}

contract BMCIlluminatiPassCandidateTest is Test {
    MockBMC bmc;
    RegisteredCoordinator coord;
    BMCIlluminatiPassCandidate pass;
    address alice = makeAddr("alice");
    uint64 deadline;

    function setUp() public {
        vm.warp(1_800_000_000);
        deadline = uint64(block.timestamp + 30 days);
        bmc = new MockBMC();
        coord = new RegisteredCoordinator();
        pass = new BMCIlluminatiPassCandidate(
            address(this), address(bmc), address(coord), deadline,
            123, coord.VALID_KEY(), 500_000, 3, true
        );
        pass.setGenesisImagesCID("bafytest");
        bmc.mint(alice, 201_000_000 ether);
        vm.startPrank(alice);
        bmc.approve(address(pass), type(uint256).max);
        for (uint256 i; i < 40; ++i) pass.mintGenesis();
        vm.stopPrank();
    }

    function _mintMystery() internal returns (uint256 tokenId) {
        vm.prank(alice);
        (tokenId,) = pass.mintMystery();
    }

    function test_BurnAndMintDoNotRequestRandomness() public {
        uint256 beforeSupply = bmc.totalSupply();
        uint256 id = _mintMystery();
        assertEq(id, 41);
        assertEq(coord.nextRequestId(), 1000);
        assertEq(bmc.totalSupply(), beforeSupply - 350_000 ether);
        assertEq(pass.requestIdOf(id), 0);
    }

    function test_UnknownGasLaneCannotRequestSeed() public {
        // Coordinator with no registered proving key must reject before request.
        RegisteredCoordinator bad = new RegisteredCoordinator();
        BMCIlluminatiPassCandidate wrong = new BMCIlluminatiPassCandidate(
            address(this), address(bmc), address(bad), uint64(block.timestamp + 1 days),
            123, keccak256("unregistered"), 500_000, 3, true
        );
        vm.warp(block.timestamp + 2 days);
        vm.expectRevert(bytes("unregistered gas lane"));
        wrong.requestSeed();
        assertEq(bad.nextRequestId(), 1000);
    }

    function test_FirstDeliveredSeedWinsAfterRetry() public {
        _mintMystery();
        vm.warp(deadline);
        uint256 first = pass.requestSeed();
        vm.expectRevert(bytes("retry too early"));
        pass.requestSeed();
        vm.warp(block.timestamp + 7 days);
        uint256 second = pass.requestSeed();
        assertTrue(second != first);
        assertTrue(coord.fulfill(second, 999));
        assertTrue(pass.seedReceived());
        assertEq(pass.globalSeed(), 999);
        assertTrue(coord.fulfill(first, 123));
        assertEq(pass.globalSeed(), 999);
        assertEq(pass.finalizeReveals(10), 1);
        assertTrue(pass.tierOf(41) != BMCIlluminatiPassCandidate.Tier.Pending);
    }

    function test_OnlyCoordinatorCanDeliverSeed() public {
        _mintMystery();
        vm.warp(deadline);
        uint256 req = pass.requestSeed();
        uint256[] memory words = new uint256[](1);
        words[0] = 55;
        vm.expectRevert(BMCIlluminatiPassCandidate.OnlyCoordinator.selector);
        pass.rawFulfillRandomWords(req, words);
        assertFalse(pass.seedReceived());
    }

    function test_FullInventoryNoDuplicates() public {
        for (uint256 i; i < 460; ++i) _mintMystery();
        uint256 req = pass.requestSeed();
        assertTrue(coord.fulfill(req, 42));
        for (uint256 i; i < 46; ++i) pass.finalizeReveals(10);
        assertEq(pass.revealedCount(), 460);
        assertEq(pass.mysteryGenesisRevealed(), 37);
        bool[78] memory genesis;
        bool[424] memory standard;
        uint256 nGenesis;
        uint256 nStandard;
        for (uint256 id = 41; id <= 500; ++id) {
            BMCIlluminatiPassCandidate.Tier tier = pass.tierOf(id);
            uint256 artwork = pass.artworkIdOf(id);
            if (tier == BMCIlluminatiPassCandidate.Tier.Genesis) {
                assertGe(artwork, 41);
                assertLe(artwork, 77);
                assertFalse(genesis[artwork]);
                genesis[artwork] = true;
                ++nGenesis;
            } else {
                assertEq(uint256(tier), uint256(BMCIlluminatiPassCandidate.Tier.Standard));
                assertGe(artwork, 1);
                assertLe(artwork, 423);
                assertFalse(standard[artwork]);
                standard[artwork] = true;
                ++nStandard;
            }
        }
        assertEq(nGenesis, 37);
        assertEq(nStandard, 423);
    }
}
