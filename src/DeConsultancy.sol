// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Import
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

contract DeConsultancy is ReentrancyGuard {
    // Type Declarations
    enum State {
        Created,
        Paid,
        Delivered,
        Completed,
        Disputed
    }

    struct Order {
        address buyer;
        address seller;
        uint256 price;
        State state;
        uint256 deliveryTime;
        uint256 deadline;
        bool disputed;
    }

    // State Variables
    mapping(uint256 => Order) public orders;
    mapping(address => uint256) public sellerPrice;

    uint256 public orderCount;
    uint256 public constant TIMEOUT = 3 days;
    address public arbiter;

    // Events
    event OrderCreated(
        uint256 indexed orderId, address indexed buyer, address indexed seller, uint256 price, uint256 deadline
    );
    event OrderDelivered(uint256 indexed orderId, string workHash);
    event RefundClaimed(uint256 indexed orderId);
    event OrderCompleted(uint256 indexed orderId);
    event AfterTimeoutClaimed(uint256 indexed orderId);
    event DisputeRaised(uint256 indexed orderId);
    event DisputeResolved(uint256 indexed orderId, address recipient);

    // Functions
    constructor(address _arbiter) {
        arbiter = _arbiter;
    }

    function setPrice(uint256 _price) public {
        sellerPrice[msg.sender] = _price;
    }

    function createOrderAndPay(address _seller, uint256 _deliveryDuration /*, string memory _requirementsHash */ )
        public
        payable
    {
        require(_seller != msg.sender, "Buyer and seller cannot be same");

        uint256 _price = sellerPrice[_seller];
        require(_price > 0, "Seller has not set a price");
        require(msg.value == _price, "Sended value does not match the price");
        require(_deliveryDuration > 0, "Invalid duration");
        require(_deliveryDuration <= 30 days, "Delivery duration too long");

        orderCount++;

        orders[orderCount] = Order({
            buyer: msg.sender,
            seller: _seller,
            price: _price,
            state: State.Paid,
            deliveryTime: 0,
            deadline: block.timestamp + _deliveryDuration,
            disputed: false
        });

        emit OrderCreated(orderCount, msg.sender, _seller, _price, block.timestamp + _deliveryDuration);
        // Store _requirementsHash on-chain or emit an event for off-chain storage
        //   requirementsHash = _requirementsHash;
    }

    function markDelivered(uint256 _orderId, string memory _workHash) public {
        Order storage order = orders[_orderId];

        require(order.buyer != address(0), "Order does not exist");
        require(block.timestamp <= order.deadline, "Delivery deadline has passed");
        require(msg.sender == order.seller, "Only seller can mark as delivered");
        require(order.state == State.Paid, "Order must be in Paid state");

        order.state = State.Delivered;
        order.deliveryTime = block.timestamp;

        emit OrderDelivered(_orderId, _workHash);
    }

    function claimRefund(uint256 _orderId) public nonReentrant {
        Order storage order = orders[_orderId];

        require(order.buyer != address(0), "Order does not exist");
        require(order.state == State.Paid, "Order must be in Paid state");
        require(msg.sender == order.buyer, "Only Buyer can claim refund");
        require(block.timestamp >= order.deadline, "Can claim only after deadline is over");

        order.state = State.Completed;

        (bool success,) = payable(order.buyer).call{value: order.price}("");
        require(success, "Refund transfer failed");

        emit RefundClaimed(_orderId);
    }

    function approveAndRelease(uint256 _orderId) public nonReentrant {
        Order storage order = orders[_orderId];

        require(order.buyer != address(0), "Order does not exist");
        require(msg.sender == order.buyer, "Only buyer can approve");
        require(order.state == State.Delivered, "Order must be deliverd to be Approved by buyer");

        order.state = State.Completed;

        /*
        This is old method
        payable(order.seller).transfer(order.price);
        */

        // This is new method, but have chance of Reentrancy
        (bool success,) = payable(order.seller).call{value: order.price}("");
        require(success, "Transfer failed");

        emit OrderCompleted(_orderId);
    }

    function claimAfterTimeout(uint256 _orderId) public nonReentrant {
        Order storage order = orders[_orderId];

        require(order.buyer != address(0), "Order does not exist");
        require(order.state == State.Delivered, "Not Delivered");
        require(block.timestamp >= order.deliveryTime + TIMEOUT, "Timeout not reached");
        require(msg.sender == order.seller, "Only seller");

        order.state = State.Completed;

        (bool success,) = payable(order.seller).call{value: order.price}("");
        require(success, "Transfer failed");

        emit AfterTimeoutClaimed(_orderId);
    }

    function raiseDispute(uint256 _orderId) public {
        Order storage order = orders[_orderId];

        require(order.buyer != address(0), "Order does not exists");
        require(msg.sender == order.buyer || msg.sender == order.seller, "Not Authorized");
        require(order.state == State.Delivered, "Can dispute only after delivery");

        order.state = State.Disputed;
        order.disputed = true;

        emit DisputeRaised(_orderId);
    }

    function resolveDispute(uint256 _orderId, bool releaseToSeller) public nonReentrant {
        Order storage order = orders[_orderId];

        require(msg.sender == arbiter, "only arbiter can resolve dispute");
        require(order.state == State.Disputed, "Order must be in disputed state");

        order.state = State.Completed;

        address recipient = releaseToSeller ? order.seller : order.buyer;

        (bool success,) = payable(recipient).call{value: order.price}("");
        require(success, "Transfer failed");

        emit DisputeResolved(_orderId, recipient);
    }

    function resolveSplit(uint256 _orderId, uint256 sellerAmount) public nonReentrant {
        Order storage order = orders[_orderId];

        require(msg.sender == arbiter, "only arbiter can resolve dispute");
        require(order.state == State.Disputed, "Order must be in disputed state");
        require(sellerAmount <= order.price, "Seller amount cannot exceed total price");

        order.state = State.Completed;

        uint256 buyerAmount = order.price - sellerAmount;

        if (sellerAmount > 0) {
            (bool success,) = payable(order.seller).call{value: sellerAmount}("");
            require(success, "Transfer to seller failed");
        }
        if (buyerAmount > 0) {
            (bool success,) = payable(order.buyer).call{value: buyerAmount}("");
            require(success, "Transfer to buyer failed");
        }
    }
}

// Multiple arbiters (DAO voting)
// Reputation system for buyers/sellers
// Escrow fees (your revenue model)
// Milestone-based payments
