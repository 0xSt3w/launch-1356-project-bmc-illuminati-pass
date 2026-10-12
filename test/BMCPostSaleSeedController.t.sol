// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {BMCPostSaleSeedController} from "../src/experimental/BMCPostSaleSeedController.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

contract DemoCoordinator {
    uint256 public nextId = 1;
    function requestRandomWords(VRFV2PlusClient.RandomWordsRequest calldata) external returns (uint256) {
        return nextId++;
    }
    function fulfill(address consumer, uint256 id, uint256 word) external {
        uint256[] memory words = new uint256[](1);
        words[0] = word;
        BMCPostSaleSeedController(consumer).rawFulfillRandomWords(id, words);
    }
}
contract BMCPostSaleSeedControllerTest is Test {
    DemoCoordinator coord;
    BMCPostSaleSeedController demo;
    function setUp() public {
        coord = new DemoCoordinator();
        demo = new BMCPostSaleSeedController(address(coord), 1, keccak256("demo"),
            500_000, 3, true, block.timestamp + 30 days, 7 days);
    }
    function testCannotRequestBeforeClose() public {
        vm.expectRevert(BMCPostSaleSeedController.NotClosed.selector);
        demo.requestSeed();
    }
    function testAnyoneCanCloseAfterDeadline() public {
        vm.warp(block.timestamp + 31 days);
        vm.prank(makeAddr("stranger"));
        demo.closeSale();
        assertTrue(demo.closed());
    }
    function testCannotRetryEarlyAndFirstDeliveredWins() public {
        vm.warp(block.timestamp + 31 days);
        demo.closeSale();
        uint256 first = demo.requestSeed();
        vm.expectRevert(BMCPostSaleSeedController.TooEarly.selector);
        demo.requestSeed();
        vm.warp(block.timestamp + 8 days);
        uint256 second = demo.requestSeed();
        coord.fulfill(address(demo), second, 42);
        coord.fulfill(address(demo), first, 999);
        assertEq(demo.seed(), 42);
        assertTrue(demo.received());
        vm.expectRevert(BMCPostSaleSeedController.AlreadyReceived.selector);
        demo.requestSeed();
    }
    function testZeroSeedAccepted() public {
        vm.warp(block.timestamp + 31 days);
        demo.closeSale();
        uint256 id = demo.requestSeed();
        coord.fulfill(address(demo), id, 0);
        assertTrue(demo.received());
        assertEq(demo.seed(), 0);
    }
    function testUnauthorizedFulfillmentRejected() public {
        vm.warp(block.timestamp + 31 days);
        demo.closeSale();
        uint256 id = demo.requestSeed();
        uint256[] memory words = new uint256[](1);
        words[0] = 123;
        vm.expectRevert(BMCPostSaleSeedController.NotCoordinator.selector);
        demo.rawFulfillRandomWords(id, words);
    }
}
