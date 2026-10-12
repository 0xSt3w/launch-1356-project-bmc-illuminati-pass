// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IBMCToken} from "../interfaces/IBMCToken.sol";
import {StandardArt} from "../StandardArt.sol";

/// @title BMC Illuminati Pass — deterministic allocation candidate
/// @notice No randomness, oracle, or reveal stage. Artwork is fixed by token ID.
/// @dev EXPERIMENTAL. NOT AUDITED OR APPROVED FOR MAINNET.
/// IDs 1..40: Genesis 1..40 at 1,000,000 BMC each.
/// IDs 41..77: Genesis 41..77 at 350,000 BMC each.
/// IDs 78..500: Standard 1..423 at 350,000 BMC each.
/// Genesis and Standard supply figures are MAXIMUMS, not guaranteed mint totals.
contract BMCIlluminatiPassDeterministic is ERC721, ReentrancyGuard {
    using Strings for uint256;

    // ------------------------------------------------------------------------------------------
    // Types
    // ------------------------------------------------------------------------------------------

    enum Tier { Pending, LegendaryGenesis, Genesis, Standard }
    enum RevealStatus { None, AwaitingRandomness, RandomnessStored, Revealed }

    // ------------------------------------------------------------------------------------------
    // Constants
    // ------------------------------------------------------------------------------------------

    uint256 public constant MAX_SUPPLY = 500;
    uint256 public constant GENESIS_PHASE_SUPPLY = 40;
    uint256 public constant MYSTERY_SUPPLY = 460;
    uint256 public constant TOTAL_GENESIS = 77;
    uint256 public constant MYSTERY_GENESIS = 37;
    uint256 public constant TOTAL_STANDARD = 423;

    /// @dev BMC has 18 decimals (verified on mainnet; also re-checked on every mint).
    uint8 public constant BMC_DECIMALS = 18;
    uint256 public constant GENESIS_PRICE = 1_000_000 * 1e18;
    uint256 public constant MYSTERY_PRICE = 350_000 * 1e18;
    /// @dev 40 * 1,000,000 + 460 * 350,000 = 201,000,000 BMC.
    uint256 public constant MAX_TOTAL_BURN = 201_000_000 * 1e18;

    IBMCToken public immutable BMC;

    // ------------------------------------------------------------------------------------------
    // Storage
    // ------------------------------------------------------------------------------------------

    uint256 public totalMinted;
    uint256 public totalBurned;
    string public genesisImagesCID;
    uint64 public immutable saleDeadline;
    bool public saleClosed;

    mapping(uint256 => Tier) private _tier;
    mapping(uint256 => uint16) private _artworkId;

    // ------------------------------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------------------------------

    event SaleClosed(uint256 minted);
    event GenesisMinted(address indexed minter, uint256 indexed tokenId, uint16 artworkId, uint256 bmcBurned);
    event MysteryMinted(address indexed minter, uint256 indexed tokenId, uint256 indexed requestId, uint256 bmcBurned);
    event Revealed(uint256 indexed tokenId, Tier tier, uint16 artworkId);

    error EmptyCID();
    error GenesisPhaseOver();
    error GenesisPhaseNotOver();
    error SoldOut();
    error UnexpectedTokenDecimals(uint8 actual);
    error BurnMismatch(uint256 expected, uint256 actual);
    error NonexistentToken(uint256 tokenId);

    // ------------------------------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------------------------------

    /// @param bmcToken Existing BMC ERC-20 token address.
    /// @param closingTime Future timestamp when minting ends.
    /// @param initialGenesisCID Bare IPFS directory CID for genesis-01.png ... genesis-77.png.
    constructor(address bmcToken, uint64 closingTime, string memory initialGenesisCID)
        ERC721("BMC Illuminati Pass", "BMCPASS")
    {
        require(bmcToken != address(0), "zero BMC");
        require(closingTime > block.timestamp, "deadline must be future");
        if (bytes(initialGenesisCID).length == 0) revert EmptyCID();
        BMC = IBMCToken(bmcToken);
        saleDeadline = closingTime;
        genesisImagesCID = initialGenesisCID;
    }

    // ------------------------------------------------------------------------------------------
    // Minting
    // ------------------------------------------------------------------------------------------

    /// @notice Phase 1: mint the next sequential Genesis NFT (ids 1-40) for 1,000,000 BMC.
    function mintGenesis() external nonReentrant returns (uint256 tokenId) {
        if (saleClosed || block.timestamp >= saleDeadline || totalMinted >= GENESIS_PHASE_SUPPLY) revert GenesisPhaseOver();

        _burnExact(msg.sender, GENESIS_PRICE);

        tokenId = ++totalMinted;
        Tier tier = tokenId == 1 ? Tier.LegendaryGenesis : Tier.Genesis;
        _tier[tokenId] = tier;
        _artworkId[tokenId] = uint16(tokenId);
        emit GenesisMinted(msg.sender, tokenId, uint16(tokenId), GENESIS_PRICE);
        emit Revealed(tokenId, tier, uint16(tokenId));

        _safeMint(msg.sender, tokenId);
    }

    /// @notice Mint next deterministically allocated token. This is NOT a mystery or random mint.
    /// @dev Kept mintMystery name for legacy UI compatibility; requestId is always zero.
    function mintMystery() external nonReentrant returns (uint256 tokenId, uint256 requestId) {
        if (totalMinted < GENESIS_PHASE_SUPPLY) revert GenesisPhaseNotOver();
        if (saleClosed || block.timestamp >= saleDeadline || totalMinted >= MAX_SUPPLY) revert SoldOut();
        _burnExact(msg.sender, MYSTERY_PRICE);
        tokenId = ++totalMinted;
        Tier tier;
        uint16 artwork;
        if (tokenId <= TOTAL_GENESIS) {
            tier = Tier.Genesis;
            artwork = uint16(tokenId);
        } else {
            tier = Tier.Standard;
            artwork = uint16(tokenId - TOTAL_GENESIS);
        }
        _tier[tokenId] = tier;
        _artworkId[tokenId] = artwork;
        emit MysteryMinted(msg.sender, tokenId, 0, MYSTERY_PRICE);
        emit Revealed(tokenId, tier, artwork);
        _safeMint(msg.sender, tokenId);
        return (tokenId, 0);
    }

    /// @notice Close when sold out or the immutable deadline has passed.
    function closeSale() public {
        require(!saleClosed, "already closed");
        require(totalMinted == MAX_SUPPLY || block.timestamp >= saleDeadline, "not closed yet");
        saleClosed = true;
        emit SaleClosed(totalMinted);
    }

    /// @dev Burns exactly `amount` BMC from `payer` via burnFrom and verifies the burn happened.
    function _burnExact(address payer, uint256 amount) private {
        uint8 dec = BMC.decimals();
        if (dec != BMC_DECIMALS) revert UnexpectedTokenDecimals(dec);
        uint256 supplyBefore = BMC.totalSupply();
        uint256 balanceBefore = BMC.balanceOf(payer);
        BMC.burnFrom(payer, amount);
        uint256 supplyDelta = supplyBefore - BMC.totalSupply();
        uint256 balanceDelta = balanceBefore - BMC.balanceOf(payer);
        if (supplyDelta != amount || balanceDelta != amount) revert BurnMismatch(amount, supplyDelta);
        totalBurned += amount;
        assert(totalBurned <= MAX_TOTAL_BURN);
    }

    // ------------------------------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------------------------------

    function tierOf(uint256 tokenId) external view returns (Tier) {
        _requireMinted(tokenId);
        return _tier[tokenId];
    }

    /// @notice Artwork identifier: for Genesis tiers the genesis-NN number (1..77); for Standard the
    ///         on-chain artwork index (1..423); 0 while pending.
    function artworkIdOf(uint256 tokenId) external view returns (uint16) {
        _requireMinted(tokenId);
        return _artworkId[tokenId];
    }

    function revealStatusOf(uint256 tokenId) external view returns (RevealStatus) {
        _requireMinted(tokenId);
        return RevealStatus.Revealed;
    }

    function totalSupply() external view returns (uint256) {
        return totalMinted;
    }

    function remainingSupply() external view returns (uint256) {
        return MAX_SUPPLY - totalMinted;
    }

    function genesisPhaseActive() external view returns (bool) {
        return !saleClosed && block.timestamp < saleDeadline && totalMinted < GENESIS_PHASE_SUPPLY;
    }

    /// @notice Remaining deterministic second-phase positions while the sale is open.
    function remainingMysteryMints() external view returns (uint256) {
        if (saleClosed || block.timestamp >= saleDeadline) return 0;
        return totalMinted < GENESIS_PHASE_SUPPLY ? MYSTERY_SUPPLY : MAX_SUPPLY - totalMinted;
    }

    function pendingReveals() external pure returns (uint256) { return 0; }

    function remainingMysteryGenesis() external view returns (uint256) {
        if (saleClosed || block.timestamp >= saleDeadline) return 0;
        return totalMinted < TOTAL_GENESIS ? TOTAL_GENESIS - (totalMinted > 40 ? totalMinted : 40) : 0;
    }

    function remainingMysteryStandard() external view returns (uint256) {
        if (saleClosed || block.timestamp >= saleDeadline) return 0;
        return totalMinted < TOTAL_GENESIS ? TOTAL_STANDARD : MAX_SUPPLY - totalMinted;
    }

    /// @notice Current price of the next mint in BMC units, 0 when sold out.
    function currentPrice() external view returns (uint256) {
        if (saleClosed || block.timestamp >= saleDeadline || totalMinted >= MAX_SUPPLY) return 0;
        return totalMinted < GENESIS_PHASE_SUPPLY ? GENESIS_PRICE : MYSTERY_PRICE;
    }

    function _requireMinted(uint256 tokenId) private view {
        if (tokenId == 0 || tokenId > totalMinted) revert NonexistentToken(tokenId);
    }

    // ------------------------------------------------------------------------------------------
    // Metadata (fully on-chain JSON)
    // ------------------------------------------------------------------------------------------

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireMinted(tokenId);
        Tier tier = _tier[tokenId];
        string memory json;
        if (tier == Tier.Pending) {
            json = _pendingJson(tokenId);
        } else if (tier == Tier.Standard) {
            json = _standardJson(tokenId, _artworkId[tokenId]);
        } else {
            json = _genesisJson(tokenId, tier, _artworkId[tokenId]);
        }
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    /// @notice Raw SVG of a Standard token (reverts for other tiers).
    function standardSVG(uint256 tokenId) external view returns (string memory) {
        _requireMinted(tokenId);
        require(_tier[tokenId] == Tier.Standard, "not standard");
        return StandardArt.render(_artworkId[tokenId]);
    }

    function _genesisFile(uint16 artwork) private pure returns (string memory) {
        return string.concat("genesis-", artwork < 10 ? "0" : "", uint256(artwork).toString(), ".png");
    }

    function _genesisJson(uint256 tokenId, Tier tier, uint16 artwork) private view returns (string memory) {
        bool legendary = tier == Tier.LegendaryGenesis;
        string memory file = _genesisFile(artwork);
        string memory head = string.concat(
            '{"name":"BMC Illuminati Pass #',
            tokenId.toString(),
            legendary ? " - Legendary Genesis" : " - Genesis",
            '","description":"',
            legendary
                ? "The one. The first BMC Illuminati Pass ever minted: the Legendary Genesis, the first piece in a collection capped at 500 NFTs. A mysterious hooded frog with a glowing golden third eye, crowned and veiled, beneath the floating golden eye-in-triangle. Minted by permanently burning 1,000,000 BMC."
                : "A Genesis BMC Illuminati Pass. A mysterious cartoon frog in a black hooded cloak with premium gold-and-black styling, a glowing golden third eye and a floating golden eye-in-triangle. A Genesis artwork from a collection capped at 77 Genesis and 500 total NFTs minted by permanently burning BMC.",
            '","image":"ipfs://',
            genesisImagesCID,
            "/",
            file
        );
        string memory attrs = string.concat(
            '","attributes":[{"trait_type":"Tier","value":"',
            legendary ? "Legendary Genesis" : "Genesis",
            '"},{"trait_type":"Artwork","value":"',
            file,
            '"},{"trait_type":"Cloak","value":"Black Hooded, Gold Trim"},{"trait_type":"Third Eye","value":"Glowing Gold"},{"trait_type":"Sigil","value":"Floating Golden Eye-in-Triangle"}',
            legendary
                ? ',{"trait_type":"Crown","value":"Legendary Golden Crown"},{"trait_type":"Aura","value":"Radiant Gold Halo"},{"trait_type":"Rank","value":"First Minter"}'
                : "",
            ',{"trait_type":"Genesis Number","display_type":"number","value":',
            uint256(artwork).toString(),
            "}]}"
        );
        return string.concat(head, attrs);
    }

    function _standardJson(uint256 tokenId, uint16 artwork) private pure returns (string memory) {
        return string.concat(
            '{"name":"BMC Illuminati Pass #',
            tokenId.toString(),
            ' - Standard","description":"A Standard BMC Illuminati Pass. An original cartoon frog in a dark hooded cloak, rendered fully on-chain as SVG. A Standard artwork from a collection capped at 423 Standard and 500 total NFTs minted by permanently burning BMC.","image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(StandardArt.render(artwork))),
            '","attributes":[{"trait_type":"Tier","value":"Standard"},{"trait_type":"Artwork","value":"standard-',
            uint256(artwork).toString(),
            '"},',
            StandardArt.attributesJson(artwork),
            "]}"
        );
    }

}
