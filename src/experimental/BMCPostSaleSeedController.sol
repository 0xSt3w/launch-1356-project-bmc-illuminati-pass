// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IVRFCoordinatorV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/// @notice EXPERIMENTAL, NOT AUDITED, NOT FOR DEPLOYMENT.
/// @dev Demonstrates permissionless post-sale VRF request and first-delivered-word-wins.
///      Not integrated with BMC minting, artwork or rarity allocation.
contract BMCPostSaleSeedController {
    IVRFCoordinatorV2Plus public immutable coordinator;
    uint256 public immutable subscriptionId;
    bytes32 public immutable keyHash;
    uint32 public immutable callbackGasLimit;
    uint16 public immutable confirmations;
    bool public immutable nativePayment;
    uint256 public immutable closingTime;
    uint256 public immutable retryDelay;
    uint256 public constant MAX_MYSTERY = 460;

    uint256 public mysteryMinted;
    bool public closed;
    bool public received;
    uint256 public seed;
    uint256 public lastRequestAt;
    uint256 public requestCount;
    mapping(uint256 => bool) public issuedRequest;

    error NotCoordinator();
    error InvalidConfig();
    error NotClosed();
    error AlreadyClosed();
    error AlreadyReceived();
    error TooEarly();
    error UnknownRequest();

    event SaleClosed(uint256 count);
    event SeedRequested(uint256 indexed requestId);
    event SeedReceived(uint256 indexed requestId, uint256 seed);

    constructor(
        address coordinator_, uint256 subscriptionId_, bytes32 keyHash_,
        uint32 callbackGasLimit_, uint16 confirmations_, bool nativePayment_,
        uint256 closingTime_, uint256 retryDelay_
    ) {
        if (coordinator_ == address(0) || subscriptionId_ == 0 || keyHash_ == bytes32(0)
            || callbackGasLimit_ < 150_000 || confirmations_ < 3
            || closingTime_ <= block.timestamp || retryDelay_ < 7 days) revert InvalidConfig();
        coordinator = IVRFCoordinatorV2Plus(coordinator_);
        subscriptionId = subscriptionId_;
        keyHash = keyHash_;
        callbackGasLimit = callbackGasLimit_;
        confirmations = confirmations_;
        nativePayment = nativePayment_;
        closingTime = closingTime_;
        retryDelay = retryDelay_;
    }

    /// @dev DEMO ONLY. Production must replace with atomic paid mint accounting.
    function recordMintForDemo() external {
        if (closed || block.timestamp >= closingTime || mysteryMinted >= MAX_MYSTERY) revert AlreadyClosed();
        ++mysteryMinted;
    }

    function closeSale() external {
        if (closed) revert AlreadyClosed();
        if (mysteryMinted != MAX_MYSTERY && block.timestamp < closingTime) revert TooEarly();
        closed = true;
        emit SaleClosed(mysteryMinted);
    }

    function requestSeed() external returns (uint256 requestId) {
        if (!closed) revert NotClosed();
        if (received) revert AlreadyReceived();
        if (requestCount != 0 && block.timestamp < lastRequestAt + retryDelay) revert TooEarly();
        // No replacement request invalidates an earlier request.
        requestId = coordinator.requestRandomWords(VRFV2PlusClient.RandomWordsRequest({
            keyHash: keyHash, subId: subscriptionId, requestConfirmations: confirmations,
            callbackGasLimit: callbackGasLimit, numWords: 1,
            extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: nativePayment}))
        }));
        if (issuedRequest[requestId]) revert InvalidConfig();
        issuedRequest[requestId] = true;
        ++requestCount;
        lastRequestAt = block.timestamp;
        emit SeedRequested(requestId);
    }

    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata words) external {
        if (msg.sender != address(coordinator)) revert NotCoordinator();
        if (!issuedRequest[requestId]) revert UnknownRequest();
        if (received) return;
        if (words.length == 0) revert InvalidConfig();
        received = true;
        seed = words[0]; // zero is a valid seed: use received flag
        emit SeedReceived(requestId, words[0]);
    }
}
