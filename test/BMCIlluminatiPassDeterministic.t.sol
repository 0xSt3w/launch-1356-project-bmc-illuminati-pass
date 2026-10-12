// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {BMCIlluminatiPassDeterministic} from "../src/experimental/BMCIlluminatiPassDeterministic.sol";
import {MockBMC} from "./mocks/MockBMC.sol";

contract BMCIlluminatiPassDeterministicTest is Test {
    MockBMC bmc;
    BMCIlluminatiPassDeterministic pass;
    address alice = makeAddr("alice");
    uint64 deadline;
    string constant CID = "bafybeihfihwwpev4gkqjuqawgtptsv3ynzsokclo6odsolvoa65aqaac2u";

    function setUp() public {
        vm.warp(1_800_000_000);
        deadline = uint64(block.timestamp + 30 days);
        bmc = new MockBMC();
        pass = new BMCIlluminatiPassDeterministic(address(bmc), deadline, CID);
        bmc.mint(alice, 201_000_000 ether);
        vm.prank(alice);
        bmc.approve(address(pass), type(uint256).max);
    }

    function _mint40() internal {
        vm.startPrank(alice);
        for (uint256 i; i < 40; ++i) pass.mintGenesis();
        vm.stopPrank();
    }

    function test_ConstructorCIDAndDeadline() public view {
        assertEq(pass.genesisImagesCID(), CID);
        assertEq(pass.saleDeadline(), deadline);
        assertEq(pass.pendingReveals(), 0);
    }

    function test_EmptyCIDReverts() public {
        vm.expectRevert(BMCIlluminatiPassDeterministic.EmptyCID.selector);
        new BMCIlluminatiPassDeterministic(address(bmc), deadline, "");
    }

    function test_CannotMintSecondPhaseBefore40() public {
        vm.prank(alice);
        vm.expectRevert(BMCIlluminatiPassDeterministic.GenesisPhaseNotOver.selector);
        pass.mintMystery();
    }

    function test_GenesisAndBoundaryAssignments() public {
        _mint40();
        assertEq(uint256(pass.tierOf(1)), uint256(BMCIlluminatiPassDeterministic.Tier.LegendaryGenesis));
        assertEq(pass.artworkIdOf(40), 40);
        vm.startPrank(alice);
        for (uint256 i; i < 38; ++i) pass.mintMystery();
        vm.stopPrank();
        assertEq(uint256(pass.tierOf(41)), uint256(BMCIlluminatiPassDeterministic.Tier.Genesis));
        assertEq(pass.artworkIdOf(41), 41);
        assertEq(uint256(pass.tierOf(77)), uint256(BMCIlluminatiPassDeterministic.Tier.Genesis));
        assertEq(pass.artworkIdOf(77), 77);
        assertEq(uint256(pass.tierOf(78)), uint256(BMCIlluminatiPassDeterministic.Tier.Standard));
        assertEq(pass.artworkIdOf(78), 1);
        assertEq(uint256(pass.revealStatusOf(78)), uint256(BMCIlluminatiPassDeterministic.RevealStatus.Revealed));
        assertEq(pass.pendingReveals(), 0);
    }

    function test_Full500UniqueAndExactBurn() public {
        _mint40();
        vm.startPrank(alice);
        for (uint256 i; i < 460; ++i) pass.mintMystery();
        vm.stopPrank();
        assertEq(pass.totalMinted(), 500);
        assertEq(pass.totalBurned(), 201_000_000 ether);
        assertEq(bmc.balanceOf(alice), 0);
        assertEq(pass.artworkIdOf(500), 423);
        assertEq(uint256(pass.tierOf(500)), uint256(BMCIlluminatiPassDeterministic.Tier.Standard));
        assertEq(pass.remainingSupply(), 0);
        vm.prank(alice);
        vm.expectRevert(BMCIlluminatiPassDeterministic.SoldOut.selector);
        pass.mintMystery();
    }

    function test_DeadlineClosesMinting() public {
        _mint40();
        vm.warp(deadline);
        assertEq(pass.currentPrice(), 0);
        assertEq(pass.remainingMysteryMints(), 0);
        vm.prank(alice);
        vm.expectRevert(BMCIlluminatiPassDeterministic.SoldOut.selector);
        pass.mintMystery();
        pass.closeSale();
        assertTrue(pass.saleClosed());
    }

    function test_NoRandomnessRequiredAndMetadataImmediate() public {
        _mint40();
        vm.prank(alice);
        (uint256 id, uint256 requestId) = pass.mintMystery();
        assertEq(requestId, 0);
        assertEq(id, 41);
        assertEq(pass.pendingReveals(), 0);
        assertGt(bytes(pass.tokenURI(id)).length, 50);
    }
}
