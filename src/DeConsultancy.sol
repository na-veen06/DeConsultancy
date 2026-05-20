// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Import
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title DeConsultancy - Decentralized Freelance Escrow Platform
 * @author Naveen Shirodkar
 * @notice A trustless escrow system for freelance and consultancy services with built-in dispute resolution and arbitration.
 *
 * @dev This contract enables buyers to create orders and lock funds in escrow while sellers must explicitly
 * accept work before starting. Accepted orders follow a structured workflow where sellers deliver services
 * off-chain and funds are released only upon buyer approval, seller timeout claims, refund conditions,
 * or dispute resolution.
 *
 * Key Features:
 * - Escrow-based payment system between buyers and sellers
 * - Seller acceptance workflow before work begins
 * - Time-bound delivery and refund mechanisms
 * - Buyer cancellation of unaccepted orders after timeout * - Dispute resolution via majority voting by arbiters
 * - Manual split resolution by arbiters (trusted override)
 * - Automatic fallback resolution after dispute timeout
 * - Platform fee deduction from seller earnings
 *
 * Order Lifecycle:
 * Paid → InProgress → Delivered → Completed
 *                              ↘
 *                                 Disputed
 *
 * Design Considerations:
 * - Funds are transferred immediately (no withdrawal pattern)
 * - Minimal on-chain storage using hashes for requirements and delivered work
 * - Reentrancy protection for all fund transfer functions
 * - Delivery deadlines begin only after seller acceptance
 */

contract DeConsultancy is ReentrancyGuard {
    //Errors

    /// @notice Thrown when buyer and seller addresses are the same
    error DeConsultancy__BuyerSellerSame();

    /// @notice Thrown when caller is not the seller
    error DeConsultancy__NotSeller();

    /// @notice Thrown when caller is not the buyer
    error DeConsultancy__NotBuyer();

    /// @notice Thrown when caller is neither buyer nor seller
    error DeConsultancy__Unauthorized();

    /// @notice Thrown when caller is not an authorized arbiter
    error DeConsultancy__NotArbiter();

    /// @notice Thrown when seller has not set a price
    error DeConsultancy__PriceNotSet();

    /// @notice Thrown when incorrect ETH amount is sent
    error DeConsultancy__IncorrectPrice();

    /// @notice Thrown when order does not exist
    error DeConsultancy__OrderNotExist();

    /// @notice Thrown when function is called in invalid order state
    error DeConsultancy__InvalidState();

    /// @notice Thrown when the order is already disputed
    error DeConsultancy__AlreadyDisputed();

    /// @notice Thrown when dispute or order is already resolved
    error DeConsultancy__AlreadyResolved();

    /// @notice Thrown when arbiter has already voted
    error DeConsultancy__AlreadyVoted();

    /// @notice Thrown when delivery duration is zero
    error DeConsultancy__InvalidDuration();

    /// @notice Thrown when delivery duration exceeds allowed limit
    error DeConsultancy__DurationTooLong();

    /// @notice Thrown when accept timeout has not been reached
    error DeConsultancy__AcceptTimeoutNotReached();

    /// @notice Thrown when delivery deadline has passed
    error DeConsultancy__DeadlinePassed();

    /// @notice Thrown when deadline has not yet passed
    error DeConsultancy__DeadlineNotPassed();

    /// @notice Thrown when required timeout period has not been reached
    error DeConsultancy__TimeoutNotReached();

    // Type Declarations
    enum State {
        Created,
        Paid,
        InProgress,
        Delivered,
        Completed,
        Disputed
    }

    struct Order {
        address buyer;
        address seller;
        uint256 price;
        State state;
        uint256 createdAt;
        uint256 deliveryDuration;
        uint256 acceptedAt;
        uint256 deliveryTime;
        uint256 deadline;
        bool disputed;
        bytes32 requirementsHash;
    }

    // State Variables
    mapping(uint256 => Order) public orders;
    mapping(address => uint256) public sellerPrice;
    mapping(address => bool) public isArbiter;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(uint256 => uint256) public sellerVotes;
    mapping(uint256 => uint256) public buyerVotes;
    mapping(uint256 => uint256) public disputeStartTime;
    mapping(uint256 => bool) public disputeResolved;

    address[] public arbiters;

    uint256 public orderCount;
    uint256 public constant TIMEOUT = 3 days;
    uint256 public constant DISPUTE_TIMEOUT = 3 days;
    uint256 public constant ACCEPT_TIMEOUT = 2 days;
    uint256 public feePercentage = 2;
    address public feeRecipient;

    // Events

    /// @notice Emitted when a new order is created and payment is locked in escrow
    /// @param orderId Unique ID of the order
    /// @param buyer Address of the buyer
    /// @param seller Address of the seller
    /// @param price Amount locked in escrow (in wei)
    /// @param deliveryDuration Delivery duration (in seconds) allocated after seller acceptance
    /// @param requirementsHash Hash of buyer requirements (off-chain data)
    event OrderCreated(
        uint256 indexed orderId,
        address indexed buyer,
        address indexed seller,
        uint256 price,
        uint256 deliveryDuration,
        bytes32 requirementsHash
    );

    /**
     * @notice Emitted when seller accepts an order
     * @param orderId Order ID of the order
     * @param seller Address of the seller
     */
    event OrderAccepted(uint256 indexed orderId, address indexed seller);

    /// @notice Emitted when buyer cancels an unaccepted order after timeout
    /// @param orderId ID of the cancelled order
    event OrderCancelled(uint256 indexed orderId);

    /// @notice Emitted when seller marks the order as delivered
    /// @param orderId ID of the order
    /// @param workHash Hash of delivered work (off-chain reference)
    event OrderDelivered(uint256 indexed orderId, string workHash);

    /// @notice Emitted when buyer successfully claims refund after deadline
    /// @param orderId ID of the order
    event RefundClaimed(uint256 indexed orderId);

    /// @notice Emitted when order is successfully completed and funds are released
    /// @param orderId ID of the order
    event OrderCompleted(uint256 indexed orderId);

    /// @notice Emitted when seller claims payment after buyer inactivity timeout
    /// @param orderId ID of the order
    event AfterTimeoutClaimed(uint256 indexed orderId);

    /// @notice Emitted when a dispute is raised for an order
    /// @param orderId ID of the disputed order
    event DisputeRaised(uint256 indexed orderId);

    /// @notice Emitted when an arbiter casts a vote on a dispute
    /// @param orderId ID of the disputed order
    /// @param arbiter Address of the arbiter who voted
    /// @param voteSeller True if vote is in favor of seller, false for buyer
    event Voted(uint256 indexed orderId, address indexed arbiter, bool voteSeller);

    /// @notice Emitted when a dispute is resolved in favor of one party
    /// @param orderId ID of the disputed order
    /// @param recipient Address receiving the funds (buyer or seller)
    event DisputeResolved(uint256 indexed orderId, address recipient);

    /// @notice Emitted when dispute is resolved by splitting funds
    /// @param orderId ID of the disputed order
    /// @param sellerAmount Amount transferred to seller after fee deduction
    /// @param buyerAmount Amount refunded to buyer
    event DisputeResolvedSplit(uint256 indexed orderId, uint256 sellerAmount, uint256 buyerAmount);

    // Functions
    constructor(address[] memory _arbiters, address _feeRecipient) {
        for (uint256 i = 0; i < _arbiters.length; i++) {
            isArbiter[_arbiters[i]] = true;
            arbiters.push(_arbiters[i]);
        }
        feeRecipient = _feeRecipient;
    }

    /// @notice Sets the service price for the seller
    /// @dev Each seller can define their own fixed price for orders
    /// @param _price The price (in wei) that buyers must pay to create an order
    function setPrice(uint256 _price) public {
        sellerPrice[msg.sender] = _price;
    }

    /// @notice Calculates platform fee for a given amount
    /// @param _amount Amount on which fee is calculated
    /// @return Fee amount in wei
    function _calculateFee(uint256 _amount) internal view returns (uint256) {
        return (_amount * feePercentage) / 100;
    }

    /// @notice Checks if dispute has reached majority and resolves automatically
    /// @dev Called after each arbiter vote
    /// @param _orderId ID of the disputed order
    function _checkAndResolve(uint256 _orderId) internal {
        uint256 requiredVote = arbiters.length / 2 + 1;

        if (sellerVotes[_orderId] >= requiredVote) {
            _resolveSeller(_orderId);
        } else if (buyerVotes[_orderId] >= requiredVote) {
            _resolveBuyer(_orderId);
        }
    }

    /// @notice Internal function to resolve dispute in favor of seller
    /// @dev Transfers funds to seller after deducting platform fee
    /// @param _orderId ID of the disputed order
    function _resolveSeller(uint256 _orderId) internal nonReentrant {
        Order storage order = orders[_orderId];

        if (order.state != State.Disputed) {
            revert DeConsultancy__InvalidState();
        }

        if (disputeResolved[_orderId]) {
            revert DeConsultancy__AlreadyResolved();
        }

        disputeResolved[_orderId] = true;
        order.state = State.Completed;

        uint256 fee = _calculateFee(order.price);
        uint256 sellerAmount = order.price - fee;

        (bool successSeller,) = payable(order.seller).call{value: sellerAmount}("");
        require(successSeller, "Transfer to seller failed");

        (bool successFee,) = payable(feeRecipient).call{value: fee}("");
        require(successFee, "Transfer of fee failed");

        delete sellerVotes[_orderId];
        delete buyerVotes[_orderId];

        emit DisputeResolved(_orderId, order.seller);
    }

    /// @notice Internal function to resolve dispute in favor of buyer
    /// @dev Refunds full amount to buyer
    /// @param _orderId ID of the disputed order
    function _resolveBuyer(uint256 _orderId) internal nonReentrant {
        Order storage order = orders[_orderId];

        if (order.state != State.Disputed) {
            revert DeConsultancy__InvalidState();
        }
        if (disputeResolved[_orderId]) {
            revert DeConsultancy__AlreadyResolved();
        }

        disputeResolved[_orderId] = true;
        order.state = State.Completed;

        (bool success,) = payable(order.buyer).call{value: order.price}("");
        require(success, "Transfer failed");

        delete sellerVotes[_orderId];
        delete buyerVotes[_orderId];

        emit DisputeResolved(_orderId, order.buyer);
    }

    /// @notice Creates a new order and locks payment in escrow
    /// @dev The buyer must send exact ETH equal to seller's set price.
    /// Delivery deadline starts only after seller accepts the order.
    /// @param _seller Address of the seller providing the service
    /// @param _deliveryDuration Time (in seconds) within which seller must deliver after acceptance
    /// @param _requirementsHash Hash of off-chain requirements (IPFS or similar)
    function createOrderAndPay(address _seller, uint256 _deliveryDuration, bytes32 _requirementsHash) public payable {
        if (_seller == msg.sender) {
            revert DeConsultancy__BuyerSellerSame();
        }
        uint256 _price = sellerPrice[_seller];
        if (_price == 0) {
            revert DeConsultancy__PriceNotSet();
        }
        if (msg.value != _price) {
            revert DeConsultancy__IncorrectPrice();
        }
        if (_deliveryDuration == 0) {
            revert DeConsultancy__InvalidDuration();
        }
        if (_deliveryDuration > 30 days) {
            revert DeConsultancy__DurationTooLong();
        }

        orderCount++;

        orders[orderCount] = Order({
            buyer: msg.sender,
            seller: _seller,
            price: _price,
            state: State.Paid,
            createdAt: block.timestamp,
            deliveryDuration: _deliveryDuration,
            acceptedAt: 0,
            deliveryTime: 0,
            deadline: 0,
            disputed: false,
            requirementsHash: _requirementsHash
        });

        emit OrderCreated(orderCount, msg.sender, _seller, _price, _deliveryDuration, _requirementsHash);
    }

    /// @notice Allows buyer to cancel an unaccepted order after timeout
    /// @dev Refunds full amount if seller does not accept within ACCEPT_TIMEOUT period
    /// @param _orderId ID of the order
    function cancelUnacceptedOrder(uint256 _orderId) public nonReentrant {
        Order storage order = orders[_orderId];

        if (order.buyer == address(0)) {
            revert DeConsultancy__OrderNotExist();
        }

        if (msg.sender != order.buyer) {
            revert DeConsultancy__NotBuyer();
        }

        if (order.state != State.Paid) {
            revert DeConsultancy__InvalidState();
        }

        if (block.timestamp < order.createdAt + ACCEPT_TIMEOUT) {
            revert DeConsultancy__AcceptTimeoutNotReached();
        }

        order.state = State.Completed;

        (bool success,) = payable(order.buyer).call{value: order.price}("");

        require(success);

        emit OrderCancelled(_orderId);
    }

    /// @notice Allows seller to accept an order and begin work
    /// @dev Starts the delivery timer and moves order state to InProgress
    /// @param _orderId ID of the order
    function acceptOrder(uint256 _orderId) public {
        Order storage order = orders[_orderId];

        if (order.buyer == address(0)) {
            revert DeConsultancy__OrderNotExist();
        }
        if (msg.sender != order.seller) {
            revert DeConsultancy__NotSeller();
        }
        if (order.state != State.Paid) {
            revert DeConsultancy__InvalidState();
        }

        order.state = State.InProgress;
        order.acceptedAt = block.timestamp;

        order.deadline = block.timestamp + order.deliveryDuration;

        emit OrderAccepted(_orderId, msg.sender);
    }

    /// @notice Marks an order as delivered by the seller
    /// @dev Can only be called by seller while order is InProgress and before deadline
    /// @param _orderId ID of the order
    /// @param _workHash Hash of delivered work (stored off-chain)
    function markDelivered(uint256 _orderId, string memory _workHash) public {
        Order storage order = orders[_orderId];

        if (order.buyer == address(0)) {
            revert DeConsultancy__OrderNotExist();
        }
        if (block.timestamp > order.deadline) {
            revert DeConsultancy__DeadlinePassed();
        }
        if (msg.sender != order.seller) {
            revert DeConsultancy__NotSeller();
        }
        if (order.state != State.InProgress) {
            revert DeConsultancy__InvalidState();
        }

        order.state = State.Delivered;
        order.deliveryTime = block.timestamp;

        emit OrderDelivered(_orderId, _workHash);
    }

    /// @notice Allows buyer to claim refund if seller fails to deliver before deadline
    /// @dev Can only be called after delivery deadline has passed for and accecpted order
    /// @param _orderId ID of the order
    function claimRefund(uint256 _orderId) public nonReentrant {
        Order storage order = orders[_orderId];

        if (order.buyer == address(0)) {
            revert DeConsultancy__OrderNotExist();
        }
        if (order.state != State.InProgress) {
            revert DeConsultancy__InvalidState();
        }
        if (order.buyer != msg.sender) {
            revert DeConsultancy__NotBuyer();
        }
        if (block.timestamp < order.deadline) {
            revert DeConsultancy__DeadlineNotPassed();
        }

        order.state = State.Completed;

        (bool success,) = payable(order.buyer).call{value: order.price}("");
        require(success, "Refund transfer failed");

        emit RefundClaimed(_orderId);
    }

    /// @notice Allows buyer to approve delivery and release payment to seller
    /// @dev Deducts platform fee before transferring funds to seller
    /// @param _orderId ID of the order
    function approveAndRelease(uint256 _orderId) public nonReentrant {
        Order storage order = orders[_orderId];

        if (order.buyer == address(0)) {
            revert DeConsultancy__OrderNotExist();
        }
        if (order.state != State.Delivered) {
            revert DeConsultancy__InvalidState();
        }
        if (order.buyer != msg.sender) {
            revert DeConsultancy__NotBuyer();
        }
        order.state = State.Completed;

        uint256 fee = _calculateFee(order.price);
        uint256 sellerAmount = order.price - fee;

        (bool successSeller,) = payable(order.seller).call{value: sellerAmount}("");
        require(successSeller, "Transfer to seller failed");

        (bool successFee,) = payable(feeRecipient).call{value: fee}("");
        require(successFee, "Fee transfer failed");

        emit OrderCompleted(_orderId);
    }

    /// @notice Allows seller to claim payment if buyer is inactive after delivery
    /// @dev Can only be called after TIMEOUT period from delivery time
    /// @param _orderId ID of the order
    function claimAfterTimeout(uint256 _orderId) public nonReentrant {
        Order storage order = orders[_orderId];

        if (order.buyer == address(0)) {
            revert DeConsultancy__OrderNotExist();
        }
        if (order.state != State.Delivered) {
            revert DeConsultancy__InvalidState();
        }
        if (order.seller != msg.sender) {
            revert DeConsultancy__NotSeller();
        }
        if (block.timestamp < order.deliveryTime + TIMEOUT) {
            revert DeConsultancy__TimeoutNotReached();
        }

        order.state = State.Completed;

        uint256 fee = _calculateFee(order.price);
        uint256 sellerAmount = order.price - fee;

        (bool successSeller,) = payable(order.seller).call{value: sellerAmount}("");
        require(successSeller, "Transfer to seller failed");

        (bool successFee,) = payable(feeRecipient).call{value: fee}("");
        require(successFee, "Fee transfer failed");

        emit AfterTimeoutClaimed(_orderId);
    }

    /// @notice Raises a dispute for a delivered order
    /// @dev Can be called by either buyer or seller when disagreement occurs
    /// @param _orderId ID of the order
    function raiseDispute(uint256 _orderId) public {
        Order storage order = orders[_orderId];

        if (order.buyer == address(0)) {
            revert DeConsultancy__OrderNotExist();
        }
        if (order.disputed) {
            revert DeConsultancy__AlreadyDisputed();
        }
        if (order.state != State.Delivered) {
            revert DeConsultancy__InvalidState();
        }
        if (order.buyer != msg.sender && order.seller != msg.sender) {
            revert DeConsultancy__Unauthorized();
        }

        order.state = State.Disputed;
        order.disputed = true;

        disputeStartTime[_orderId] = block.timestamp;

        emit DisputeRaised(_orderId);
    }

    /// @notice Allows an arbiter to vote on a dispute
    /// @dev Each arbiter can vote only once per dispute; majority decides outcome
    /// @param _orderId ID of the disputed order
    /// @param voteForSeller True if voting in favor of seller, false for buyer
    function voteOnDispute(uint256 _orderId, bool voteForSeller) public {
        Order storage order = orders[_orderId];

        if (order.buyer == address(0)) {
            revert DeConsultancy__OrderNotExist();
        }
        if (!isArbiter[msg.sender]) {
            revert DeConsultancy__NotArbiter();
        }
        if (disputeResolved[_orderId]) {
            revert DeConsultancy__AlreadyResolved();
        }
        if (order.state != State.Disputed) {
            revert DeConsultancy__InvalidState();
        }
        if (hasVoted[_orderId][msg.sender]) {
            revert DeConsultancy__AlreadyVoted();
        }

        hasVoted[_orderId][msg.sender] = true;

        if (voteForSeller) {
            sellerVotes[_orderId]++;
        } else {
            buyerVotes[_orderId]++;
        }

        emit Voted(_orderId, msg.sender, voteForSeller);

        _checkAndResolve(_orderId);
    }

    /// @notice Resolves dispute by splitting funds between buyer and seller
    /// @dev Callable by an arbiter; applies fee only on seller's share
    /// @param _orderId ID of the disputed order
    /// @param sellerAmount Amount (in wei) allocated to seller before fee deduction
    /// @dev WARNING: This function allows a single arbiter to override dispute outcome.
    /// Should only be used in trusted arbitration setups.
    function resolveSplit(uint256 _orderId, uint256 sellerAmount) public nonReentrant {
        Order storage order = orders[_orderId];

        if (order.buyer == address(0)) {
            revert DeConsultancy__OrderNotExist();
        }
        if (!isArbiter[msg.sender]) {
            revert DeConsultancy__NotArbiter();
        }
        if (order.state != State.Disputed) {
            revert DeConsultancy__InvalidState();
        }
        if (sellerAmount > order.price) {
            revert DeConsultancy__IncorrectPrice();
        }
        if (disputeResolved[_orderId]) {
            revert DeConsultancy__AlreadyResolved();
        }

        disputeResolved[_orderId] = true;
        order.state = State.Completed;

        uint256 buyerAmount = order.price - sellerAmount;

        uint256 fee = _calculateFee(sellerAmount);
        uint256 sellerAmountAfterFee = sellerAmount - fee;

        if (sellerAmount > 0) {
            (bool successSeller,) = payable(order.seller).call{value: sellerAmountAfterFee}("");
            require(successSeller, "Transfer to seller failed");

            (bool successFee,) = payable(feeRecipient).call{value: fee}("");
            require(successFee, "Transfer of fee failed");
        }
        if (buyerAmount > 0) {
            (bool success,) = payable(order.buyer).call{value: buyerAmount}("");
            require(success, "Transfer to buyer failed");
        }

        delete sellerVotes[_orderId];
        delete buyerVotes[_orderId];

        emit DisputeResolvedSplit(_orderId, sellerAmountAfterFee, buyerAmount);
    }

    /// @notice Resolves dispute automatically after timeout if no majority is reached
    /// @dev Transfers full amount (minus fee) to seller by default
    /// @param _orderId ID of the disputed order
    function resolveAfterDisputeTimeout(uint256 _orderId) public nonReentrant {
        Order storage order = orders[_orderId];

        if (order.buyer == address(0)) {
            revert DeConsultancy__OrderNotExist();
        }
        if (disputeResolved[_orderId]) {
            revert DeConsultancy__AlreadyResolved();
        }
        if (order.state != State.Disputed) {
            revert DeConsultancy__InvalidState();
        }
        if (block.timestamp < disputeStartTime[_orderId] + DISPUTE_TIMEOUT) {
            revert DeConsultancy__TimeoutNotReached();
        }

        disputeResolved[_orderId] = true;
        order.state = State.Completed;

        uint256 fee = _calculateFee(order.price);
        uint256 sellerAmount = order.price - fee;

        (bool successSeller,) = payable(order.seller).call{value: sellerAmount}("");
        require(successSeller, "Seller transfer failed");

        (bool successFee,) = payable(feeRecipient).call{value: fee}("");
        require(successFee, " Fee transfer failed");

        delete sellerVotes[_orderId];
        delete buyerVotes[_orderId];

        emit DisputeResolved(_orderId, order.seller);
    }

    // Getter functions
    function getOrder(uint256 _orderId) public view returns (Order memory) {
        return orders[_orderId];
    }

    function getFeePercentage() public view returns (uint256) {
        return feePercentage;
    }

    function getOrderState(uint256 _orderId) public view returns (State) {
        return orders[_orderId].state;
    }

    function getDeliveryTime(uint256 _orderId) public view returns (uint256) {
        return orders[_orderId].deliveryTime;
    }
}
