// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {BMCIlluminatiPassDeterministic} from "../src/BMCIlluminatiPassDeterministic.sol";

/// @notice SIMULATION ONLY. No startBroadcast, private key, or network transaction.
contract DeployBMCIlluminatiPassDeterministicDryRun is Script {
    address constant BMC = 0x38224239f2BDae357D47cb864BC533d7f72dF961;
    string constant CID = "bafybeihfihwwpev4gkqjuqawgtptsv3ynzsokclo6odsolvoa65aqaac2u";

    function run() external returns (BMCIlluminatiPassDeterministic simulatedPass) {
        uint64 deadline = uint64(block.timestamp + 30 days);
        simulatedPass = new BMCIlluminatiPassDeterministic(BMC, deadline, CID);
        require(simulatedPass.saleDeadline() == deadline, "deadline mismatch");
        require(keccak256(bytes(simulatedPass.genesisImagesCID())) == keccak256(bytes(CID)), "CID mismatch");
        require(address(simulatedPass.BMC()) == BMC, "BMC mismatch");
    }
}
