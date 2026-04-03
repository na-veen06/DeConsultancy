// Layout of Contract: //
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions //
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
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

contract DeConsultancy is ReentrancyGuard {
    //Errors
    error DeConsultancy__BuyerSellerSame();
    error DeConsultancy__PriceNotSet();
    error DeConsultancy__IncorrectPrice();
    error DeConsultancy__InvalidDuration();
    error DeConsultancy__DurationTooLong();
    error DeConsultancy__OrderNotExist();
    error DeConsultancy__NotSeller();
    error DeConsultancy__NotBuyer();
    error DeConsultancy__Unauthorized();
    error DeConsultancy__NotArbiter();
    error DeConsultancy__DeadlinePassed();
    error DeConsultancy__DeadlineNotPassed();
    error DeConsultancy__InvalidState();
    error DeConsultancy__TimeoutNotReached();

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

    function createOrderAndPay(
        address _seller,
        uint256 _deliveryDuration /*, string memory _requirementsHash */
    )
        public
        payable
    {
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

        if (order.buyer == address(0)) {
            revert DeConsultancy__OrderNotExist();
        }
        if (block.timestamp > order.deadline) {
            revert DeConsultancy__DeadlinePassed();
        }
        if (msg.sender != order.seller) {
            revert DeConsultancy__NotSeller();
        }
        if (order.state != State.Paid) {
            revert DeConsultancy__InvalidState();
        }

        order.state = State.Delivered;
        order.deliveryTime = block.timestamp;

        emit OrderDelivered(_orderId, _workHash);
    }

    function claimRefund(uint256 _orderId) public nonReentrant {
        Order storage order = orders[_orderId];

        if (order.buyer == address(0)) {
            revert DeConsultancy__OrderNotExist();
        }
        if (order.state != State.Paid) {
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

        (bool success,) = payable(order.seller).call{value: order.price}("");
        require(success, "Transfer failed");

        emit AfterTimeoutClaimed(_orderId);
    }

    function raiseDispute(uint256 _orderId) public {
        Order storage order = orders[_orderId];

        if (order.buyer == address(0)) {
            revert DeConsultancy__OrderNotExist();
        }
        if (order.state != State.Delivered) {
            revert DeConsultancy__InvalidState();
        }
        if (order.buyer != msg.sender && order.seller != msg.sender) {
            revert DeConsultancy__Unauthorized();
        }

        order.state = State.Disputed;
        order.disputed = true;

        emit DisputeRaised(_orderId);
    }

    function resolveDispute(uint256 _orderId, bool releaseToSeller) public nonReentrant {
        Order storage order = orders[_orderId];

        if (msg.sender != arbiter) {
            revert DeConsultancy__NotArbiter();
        }
        if (order.state != State.Disputed) {
            revert DeConsultancy__InvalidState();
        }

        order.state = State.Completed;

        address recipient = releaseToSeller ? order.seller : order.buyer;

        (bool success,) = payable(recipient).call{value: order.price}("");
        require(success, "Transfer failed");

        emit DisputeResolved(_orderId, recipient);
    }

    function resolveSplit(uint256 _orderId, uint256 sellerAmount) public nonReentrant {
        Order storage order = orders[_orderId];

        if (msg.sender != arbiter) {
            revert DeConsultancy__NotArbiter();
        }
        if (order.state != State.Disputed) {
            revert DeConsultancy__InvalidState();
        }
        if (sellerAmount > order.price) {
            revert DeConsultancy__IncorrectPrice();
        }

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

    // Getter functions
    function getOrder(uint256 _orderId) public view returns (Order memory) {
        return orders[_orderId];
    }

    function getOrderCount() public view returns (uint256) {
        return orderCount;
    }

    function getSellerPrice(address _seller) public view returns (uint256) {
        return sellerPrice[_seller];
    }

    function getOrderState(uint256 _orderId) public view returns (State) {
        return orders[_orderId].state;
    }

    function getDeadline(uint256 _orderId) public view returns (uint256) {
        return orders[_orderId].deadline;
    }

    function getDeliveryTime(uint256 _orderId) public view returns (uint256) {
        return orders[_orderId].deliveryTime;
    }

    function orderExists(uint256 _orderId) public view returns (bool) {
        return orders[_orderId].buyer != address(0);
    }
}

// Multiple arbiters (DAO voting)
// Reputation system for buyers/sellers
// Escrow fees (your revenue model)
// Milestone-based payments
