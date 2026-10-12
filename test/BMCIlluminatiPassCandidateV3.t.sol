// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {BMCIlluminatiPassCandidateV3} from "../src/experimental/BMCIlluminatiPassCandidateV3.sol";
import {MockBMC} from "./mocks/MockBMC.sol";
import {MockVRFCoordinator} from "./mocks/MockVRFCoordinator.sol";

contract V3RegisteredCoordinator is MockVRFCoordinator {
    bytes32 public constant VALID_KEY = keccak256("registered-key");

    function s_provingKeys(bytes32 key) external pure returns (bool exists, uint64 maxGas) {
        return (key == VALID_KEY, key == VALID_KEY ? uint64(500 gwei) : uint64(0));
    }
}

contract BMCIlluminatiPassCandidateV3Test is Test {
    string internal constant GENESIS_CID = "bafybeihfihwwpev4gkqjuqawgtptsv3ynzsokclo6odsolvoa65aqaac2u";

    MockBMC bmc;
    V3RegisteredCoordinator coord;
    BMCIlluminatiPassCandidateV3 pass;
    address alice = makeAddr("alice");
    uint64 deadline;

    function _deploy(string memory cid, bytes32 key) internal returns (BMCIlluminatiPassCandidateV3) {
        return new BMCIlluminatiPassCandidateV3(
            address(this), address(bmc), address(coord), uint64(block.timestamp + 30 days),
            123, key, 500_000, 3, true, cid
        );
    }

    function setUp() public {
        vm.warp(1_800_000_000);
        deadline = uint64(block.timestamp + 30 days);
        bmc = new MockBMC();
        coord = new V3RegisteredCoordinator();
        pass = _deploy(GENESIS_CID, coord.VALID_KEY());
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

    function test_GenesisCIDSetAndLockedAtDeployment() public view {
        assertEq(pass.genesisImagesCID(), GENESIS_CID);
        assertTrue(pass.genesisCIDLocked());
    }

    function test_EmptyGenesisCIDReverts() public {
        bytes32 key = coord.VALID_KEY();
        vm.expectRevert(BMCIlluminatiPassCandidateV3.EmptyCID.selector);
        new BMCIlluminatiPassCandidateV3(
            address(this), address(bmc), address(coord), uint64(block.timestamp + 30 days),
            123, key, 500_000, 3, true, ""
        );
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
        BMCIlluminatiPassCandidateV3 wrong = _deploy(GENESIS_CID, keccak256("unregistered"));
        vm.warp(block.timestamp + 31 days);
        vm.expectRevert(bytes("unregistered gas lane"));
        wrong.requestSeed();
        assertEq(coord.nextRequestId(), 1000);
    }

    function test_OnlyOneSeedRequestEvenAfterSevenDays() public {
        _mintMystery();
        vm.warp(deadline);
        uint256 first = pass.requestSeed();
        assertEq(pass.seedRequestId(), first);
        vm.warp(block.timestamp + 8 days);
        vm.expectRevert(bytes("seed already requested"));
        pass.requestSeed();
        assertFalse(pass.seedReceived());
        assertTrue(coord.fulfill(first, 123));
        assertEq(pass.globalSeed(), 123);
        assertEq(pass.finalizeReveals(10), 1);
    }

    function test_SaleViewsCloseAtDeadline() public {
        assertFalse(pass.genesisPhaseActive()); // 40 Genesis already minted in setUp
        assertEq(pass.currentPrice(), pass.MYSTERY_PRICE());
        vm.warp(deadline);
        assertEq(pass.currentPrice(), 0);
        assertFalse(pass.genesisPhaseActive());
    }

    function test_UnrecognizedRequestRejected() public {
        _mintMystery();
        vm.warp(deadline);
        uint256 req = pass.requestSeed();
        uint256[] memory words = new uint256[](1);
        words[0] = 7;
        vm.startPrank(address(coord));
        vm.expectRevert(abi.encodeWithSelector(BMCIlluminatiPassCandidateV3.UnknownRequest.selector, req + 1));
        pass.rawFulfillRandomWords(req + 1, words);
        vm.stopPrank();
    }

    function test_OnlyCoordinatorCanDeliverSeed() public {
        _mintMystery();
        vm.warp(deadline);
        uint256 req = pass.requestSeed();
        uint256[] memory words = new uint256[](1);
        words[0] = 55;
        vm.expectRevert(BMCIlluminatiPassCandidateV3.OnlyCoordinator.selector);
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
            BMCIlluminatiPassCandidateV3.Tier tier = pass.tierOf(id);
            uint256 artwork = pass.artworkIdOf(id);
            if (tier == BMCIlluminatiPassCandidateV3.Tier.Genesis) {
                assertGe(artwork, 41);
                assertLe(artwork, 77);
                assertFalse(genesis[artwork]);
                genesis[artwork] = true;
                ++nGenesis;
            } else {
                assertEq(uint256(tier), uint256(BMCIlluminatiPassCandidateV3.Tier.Standard));
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
