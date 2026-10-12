// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {BMCPassVRFPrototype} from "../src/experimental/BMCPassVRFPrototype.sol";

/// @dev TEST-ONLY VRF consumer. Not a minting contract and never for deployment.
contract ExperimentalVRFConsumer {
    VRFCoordinatorV2_5Mock public immutable coordinator;
    uint256 public immutable subscriptionId;
    uint256 public requestId;
    bool public received;
    uint256 public seed;

    constructor(address coordinator_, uint256 subscriptionId_) {
        coordinator = VRFCoordinatorV2_5Mock(coordinator_);
        subscriptionId = subscriptionId_;
    }

    function requestOnce() external returns (uint256) {
        require(requestId == 0, "already requested");
        requestId = coordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keccak256("lane"),
                subId: subscriptionId,
                requestConfirmations: 3,
                callbackGasLimit: 500_000,
                numWords: 1,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        );
        return requestId;
    }

    function rawFulfillRandomWords(uint256 id, uint256[] calldata words) external {
        require(msg.sender == address(coordinator), "not coordinator");
        require(id == requestId && id != 0, "wrong request");
        require(!received, "already fulfilled");
        require(words.length == 1, "wrong word count");
        received = true;
        seed = words[0];
    }
}

contract BMCPassVRFChainlinkIntegrationTest is Test {
    VRFCoordinatorV2_5Mock coordinator;
    ExperimentalVRFConsumer consumer;
    BMCPassVRFPrototype prototype;
    uint256 subscriptionId;

    function setUp() public {
        coordinator = new VRFCoordinatorV2_5Mock(0.1 ether, 1e9, 4e15);
        subscriptionId = coordinator.createSubscription();
        consumer = new ExperimentalVRFConsumer(address(coordinator), subscriptionId);
        coordinator.addConsumer(subscriptionId, address(consumer));
        coordinator.fundSubscription(subscriptionId, 100 ether);
        prototype = new BMCPassVRFPrototype();
    }

    function testVRFSeedProducesExactUniqueInventory() public {
        uint256 requestId = consumer.requestOnce();
        uint256[] memory words = new uint256[](1);
        words[0] = 987654321;
        coordinator.fulfillRandomWordsWithOverride(requestId, address(consumer), words);
        assertTrue(consumer.received());
        assertEq(consumer.seed(), words[0]);

        uint16[] memory results = prototype.draw(consumer.seed());
        assertEq(results.length, 460);
        bool[460] memory seen;
        uint256 genesis;
        uint256 standard;
        for (uint256 i; i < results.length; ++i) {
            uint256 value = uint256(results[i]);
            assertLt(value, 460);
            assertFalse(seen[value], "duplicate outcome");
            seen[value] = true;
            if (prototype.tierOfOutcome(results[i]) == 2) ++genesis;
            else ++standard;
        }
        assertEq(genesis, 37);
        assertEq(standard, 423);
        assertEq(
            keccak256(abi.encode(results)),
            keccak256(abi.encode(prototype.draw(consumer.seed())))
        );
    }

    function testCannotRequestSecondSeed() public {
        consumer.requestOnce();
        vm.expectRevert("already requested");
        consumer.requestOnce();
    }

    function testOnlyCoordinatorMaySupplySeed() public {
        uint256 id = consumer.requestOnce();
        uint256[] memory words = new uint256[](1);
        words[0] = 5;
        vm.expectRevert("not coordinator");
        consumer.rawFulfillRandomWords(id, words);
        assertFalse(consumer.received());
    }

    function testUnfulfilledRequestDoesNotCreateSeed() public {
        consumer.requestOnce();
        vm.warp(block.timestamp + 200 days);
        assertFalse(consumer.received());
        assertEq(consumer.seed(), 0);
    }
}
