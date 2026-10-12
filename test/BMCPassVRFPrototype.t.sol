
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {
    BMCPassVRFPrototype
} from "../src/experimental/BMCPassVRFPrototype.sol";

contract BMCPassVRFPrototypeTest is Test {
    BMCPassVRFPrototype prototype;

    function setUp() public {
        prototype = new BMCPassVRFPrototype();
    }

    function testDistributionHasNoDuplicates() public {
        uint16[] memory outcomes = prototype.draw(123456789);

        assertEq(outcomes.length, 460);

        bool[460] memory seen;
        uint256 genesis;
        uint256 standard;

        for (uint256 i; i < outcomes.length; ++i) {
            uint16 outcome = outcomes[i];

            assertLt(uint256(outcome), 460);
            assertFalse(seen[outcome], "duplicate outcome");

            seen[outcome] = true;

            uint8 tier = prototype.tierOfOutcome(outcome);

            if (tier == 2) {
                genesis++;
            } else if (tier == 3) {
                standard++;
            } else {
                fail();
            }
        }

        assertEq(genesis, 37);
        assertEq(standard, 423);
    }

    function testSameSeedProducesSameDistribution() public {
        uint16[] memory first = prototype.draw(42);
        uint16[] memory second = prototype.draw(42);

        assertEq(keccak256(abi.encode(first)), keccak256(abi.encode(second)));
    }

    function testDifferentSeedsProduceDifferentDistributions() public {
        uint16[] memory first = prototype.draw(1);
        uint16[] memory second = prototype.draw(2);

        assertTrue(
            keccak256(abi.encode(first)) != keccak256(abi.encode(second))
        );
    }

    function testInvalidOutcomeReverts() public {
        vm.expectRevert("invalid outcome");
        prototype.tierOfOutcome(460);
    }
}
