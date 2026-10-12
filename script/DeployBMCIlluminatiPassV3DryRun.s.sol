// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {BMCIlluminatiPassCandidateV3} from "../src/experimental/BMCIlluminatiPassCandidateV3.sol";

/// @notice Simulation-only deployment script. Never broadcasts or signs a transaction.
/// @dev Run via `forge script ... --fork-url "$MAINNET_RPC_URL" -vvvv` WITHOUT --broadcast.
contract DeployBMCIlluminatiPassV3DryRun is Script {
    address internal constant BMC = 0x38224239f2BDae357D47cb864BC533d7f72dF961;
    address internal constant COORDINATOR = 0xD7f86b4b8Cae7D942340FF628F82735b7a20893a;
    uint256 internal constant SUBSCRIPTION_ID =
        27852459484169864437638942739291618120641810244677084392617474192083559562985;
    bytes32 internal constant KEY_HASH =
        0x3fd2fec10d06ee8f65e7f2e95f5c56511359ece3f33960ad8a866ae24a8ff10b;
    string internal constant GENESIS_CID =
        "bafybeihfihwwpev4gkqjuqawgtptsv3ynzsokclo6odsolvoa65aqaac2u";

    uint256 internal constant SALE_DURATION = 30 days;

    function run() external returns (BMCIlluminatiPassCandidateV3 simulatedPass) {
        require(block.chainid == 1, "Ethereum mainnet fork required");
        address owner = vm.envAddress("OWNER");
        require(owner != address(0), "OWNER must not be zero");
        require(BMC.code.length > 0 && COORDINATOR.code.length > 0, "missing mainnet contract code");
        uint256 end = block.timestamp + SALE_DURATION;
        require(end <= type(uint64).max, "deadline overflow");

        // Simulation only: deliberately no vm.startBroadcast / vm.broadcast.
        simulatedPass = new BMCIlluminatiPassCandidateV3(
            owner,
            BMC,
            COORDINATOR,
            uint64(end),
            SUBSCRIPTION_ID,
            KEY_HASH,
            500_000,
            3,
            true,
            GENESIS_CID
        );

        require(simulatedPass.owner() == owner, "owner mismatch");
        require(simulatedPass.saleDeadline() == end, "deadline mismatch");
        require(simulatedPass.genesisCIDLocked(), "CID not locked");
        require(
            keccak256(bytes(simulatedPass.genesisImagesCID())) == keccak256(bytes(GENESIS_CID)),
            "CID mismatch"
        );
    }
}
