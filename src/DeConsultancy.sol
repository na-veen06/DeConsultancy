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
pragma solidity 0.8.19;

// Import
// import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract DeConsultancy {
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
    }

    // State Variables
    mapping(uint256 => Order) public orders;
    mapping(address => uint256) public sellerPrice;

    uint256 public orderCount;

    // Events
    event OrderDelivered(uint256 indexed orderId, string workHash);
    event OrderCompleted(uint256 indexed orderId);

    // Functions
    constructor() {}

    function setPrice(uint256 _price) public {
        sellerPrice[msg.sender] = _price;
    }

    function createOrderAndPay(
        address _seller /*, string memory _requirementsHash */
    ) public payable {
        require(_seller != msg.sender, "Buyer and seller cannot be same");

        uint256 _price = sellerPrice[_seller];
        require(_price > 0, "Seller has not set a price");
        require(msg.value == _price, "Sended value does not match the price");

        orderCount++;

        orders[orderCount] = Order({
            buyer: msg.sender,
            seller: _seller,
            price: _price,
            state: State.Paid
        });

        // Store _requirementsHash on-chain or emit an event for off-chain storage
        //   requirementsHash = _requirementsHash;
    }

    function markDelivered(uint256 _orderId, string memory _workHash) public {
        Order storage order = orders[_orderId];

        require(order.buyer != address(0), "Order does not exist");
        require(
            msg.sender == order.seller,
            "Only seller can mark as delivered"
        );
        require(order.state == State.Paid, "Order must be in Paid state");

        order.state = State.Delivered;

        emit OrderDelivered(_orderId, _workHash);
    }

    function approveAndRelease(uint256 _orderId) public {
        Order storage order = orders[_orderId];

        require(order.buyer != address(0), "Order does not exist");
        require(msg.sender == order.buyer, "Only buyer can approve");
        require(
            order.state == State.Delivered,
            "Order must be deliverd to be Approved by buyer"
        );

        order.state = State.Completed;

        /*
        This is old method
        payable(order.seller).transfer(order.price);
        */

        // This is new method, but have chance of Reentrancy
        (bool success, ) = payable(order.seller).call{value: order.price}("");
        require(success, "Transfer failed");

        emit OrderCompleted(_orderId);
    }
}
