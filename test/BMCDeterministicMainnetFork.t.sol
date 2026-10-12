
 // SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {BMCIlluminatiPassDeterministic} from "../src/BMCIlluminatiPassDeterministic.sol";

interface IRealBMCDeterministic {
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

contract BMCDeterministicMainnetForkTest is Test {
    address constant BMC =
        0x38224239f2BDae357D47cb864BC533d7f72dF961;

    uint256 constant PRICE = 1_000_000 ether;

    string constant GENESIS_CID =
        "bafybeihfihwwpev4gkqjuqawgtptsv3ynzsokclo6odsolvoa65aqaac2u";

    address buyer = address(0xBEEF);

    function test_RealBMCDeterministicGenesisMint() public {
        require(block.chainid == 1, "Ethereum mainnet fork required");
        require(BMC.code.length > 0, "BMC contract missing");

        IRealBMCDeterministic token = IRealBMCDeterministic(BMC);
        assertEq(token.decimals(), 18);

        BMCIlluminatiPassDeterministic pass =
            new BMCIlluminatiPassDeterministic(
                BMC,
                uint64(block.timestamp + 30 days),
                GENESIS_CID
            );

        // Local fork only. No real token balances are changed.
        deal(BMC, buyer, PRICE, true);

        assertEq(token.balanceOf(buyer), PRICE);

        uint256 supplyBefore = token.totalSupply();

        vm.startPrank(buyer);
        token.approve(address(pass), PRICE);
        uint256 tokenId = pass.mintGenesis();
        vm.stopPrank();

        assertEq(tokenId, 1);
        assertEq(pass.ownerOf(1), buyer);
        assertEq(pass.totalBurned(), PRICE);
        assertEq(token.balanceOf(buyer), 0);
        assertEq(token.totalSupply(), supplyBefore - PRICE);
    }
}
