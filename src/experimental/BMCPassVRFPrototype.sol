
 // SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice EXPERIMENTAL ONLY — NOT FOR MAINNET DEPLOYMENT.
/// @dev Demonstrates deterministic draws without replacement.
///      Does not request randomness or mint/burn tokens.
contract BMCPassVRFPrototype {
    uint256 public constant MYSTERY_SUPPLY = 460;
    uint256 public constant GENESIS_COUNT = 37;
    uint256 public constant STANDARD_COUNT = 423;

    /// @notice Derives one of 460! possible permutations
    ///         from a supplied seed using a Fisher-Yates draw.
    /// @dev The seed MUST come from a trusted VRF source
    ///      in a future audited implementation.
    function draw(uint256 seed)
        external
        pure
        returns (uint16[] memory outcomes)
    {
        outcomes = new uint16[](MYSTERY_SUPPLY);

        uint16[460] memory pool;

        for (uint256 i; i < MYSTERY_SUPPLY; ++i) {
            pool[i] = uint16(i);
        }

        for (uint256 i; i < MYSTERY_SUPPLY; ++i) {
            uint256 remaining = MYSTERY_SUPPLY - i;

            uint256 randomIndex = uint256(
                keccak256(abi.encode(seed, i))
            ) % remaining;

            uint16 selected = pool[randomIndex];

            outcomes[i] = selected;

            pool[randomIndex] = pool[remaining - 1];
        }
    }

    /// @notice Returns the rarity category of a draw.
    /// @return 2 for Mystery Genesis, 3 for Standard.
    function tierOfOutcome(uint16 outcome)
        external
        pure
        returns (uint8)
    {
        require(outcome < MYSTERY_SUPPLY, "invalid outcome");

        return outcome < GENESIS_COUNT ? 2 : 3;
    }
}
