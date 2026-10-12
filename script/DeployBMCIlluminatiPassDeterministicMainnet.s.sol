
 // SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {BMCIlluminatiPassDeterministic} from "../src/BMCIlluminatiPassDeterministic.sol";

contract DeployBMCIlluminatiPassDeterministicMainnet is Script {
    address constant BMC =
        0x38224239f2BDae357D47cb864BC533d7f72dF961;

    string constant CID =
        "bafybeihfihwwpev4gkqjuqawgtptsv3ynzsokclo6odsolvoa65aqaac2u";

    function run() external returns (BMCIlluminatiPassDeterministic pass) {
        require(block.chainid == 1, "Ethereum Mainnet only");
        require(BMC.code.length > 0, "BMC missing");

        uint64 deadline = uint64(block.timestamp + 30 days);

        vm.startBroadcast();

        pass = new BMCIlluminatiPassDeterministic(
            BMC,
            deadline,
            CID
        );

        vm.stopBroadcast();

        require(pass.saleDeadline() == deadline, "deadline mismatch");
        require(address(pass.BMC()) == BMC, "BMC mismatch");
        require(
            keccak256(bytes(pass.genesisImagesCID())) ==
                keccak256(bytes(CID)),
            "CID mismatch"
        );
    }
}
