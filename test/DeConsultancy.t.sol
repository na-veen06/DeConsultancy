// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";

import {DeConsultancy} from "../src/DeConsultancy.sol";

contract DeConsultancyTest is Test {
    DeConsultancy deConsultancy;

    address buyer = address(1);
    address seller = address(2);

    function setUp() external {
        deConsultancy = new DeConsultancy(address(this));

        vm.deal(buyer, 10 ether);
        vm.deal(seller, 10 ether);
    }

    // Test Cases for createOrderAndPay
    function testCreateOrderAndPay() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 1 days);

        assertEq(deConsultancy.orderCount(), 1);

        DeConsultancy.Order memory order = deConsultancy.getOrder(1);

        assertEq(order.buyer, buyer);
        assertEq(order.seller, seller);
        assertEq(order.price, 1 ether);
        assertEq(uint256(order.state), uint256(DeConsultancy.State.Paid));

        // assertTrue(order.deadline > block.timestamp);
        assertEq(order.deadline, block.timestamp + 1 days);
    }

    function testCreateOrderAndPayWithIncorrectPrice() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        vm.expectRevert(DeConsultancy.DeConsultancy__IncorrectPrice.selector);
        deConsultancy.createOrderAndPay{value: 0.5 ether}(seller, 1 days);

        assertEq(deConsultancy.orderCount(), 0);
    }

    function testCreateOrderAndPayWithNoPriceSet() public {
        vm.prank(buyer);
        vm.expectRevert(DeConsultancy.DeConsultancy__PriceNotSet.selector);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 1 days);

        assertEq(deConsultancy.orderCount(), 0);
    }

    function testCreateOrderAndPayWithSameSellerAndBuyer() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(seller);
        vm.expectRevert(DeConsultancy.DeConsultancy__BuyerSellerSame.selector);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 1 days);

        assertEq(deConsultancy.orderCount(), 0);
    }

    function testCreateOrderAndPayWithInvalidDuration() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        vm.expectRevert(DeConsultancy.DeConsultancy__InvalidDuration.selector);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 0 days);

        assertEq(deConsultancy.orderCount(), 0);
    }

    function testCreateOrderAndPayWithDurationTooLong() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        vm.expectRevert(DeConsultancy.DeConsultancy__DurationTooLong.selector);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 31 days);

        assertEq(deConsultancy.orderCount(), 0);
    }

    // Event Testing for CreateOrderAndPay
    function testOrderCreatedEvent() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.expectEmit(true, true, false, true);
        emit DeConsultancy.OrderCreated(1, buyer, seller, 1 ether, block.timestamp + 1 days);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 1 days);
    }

    // Test Cases for markDelivered
    function testMarkDelivered() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        DeConsultancy.Order memory order = deConsultancy.getOrder(1);

        assertEq(order.seller, seller);
        assertEq(uint256(deConsultancy.getOrderState(1)), uint256(DeConsultancy.State.Delivered));
        assertEq(order.deliveryTime, block.timestamp);
    }

    function testMarkDeliveredIfOrderNotExist() public {
        vm.prank(seller);
        vm.expectRevert(DeConsultancy.DeConsultancy__OrderNotExist.selector);
        deConsultancy.markDelivered(1, "navee");
    }

    function testMarkDeliveredByNotSeller() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days);

        vm.prank(buyer);
        vm.expectRevert(DeConsultancy.DeConsultancy__NotSeller.selector);
        deConsultancy.markDelivered(1, "navee");
    }

    function testMarkDeliveredWithDeadlinePassed() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 6 days);

        vm.warp(block.timestamp + 7 days);
        vm.prank(seller);

        vm.expectRevert(DeConsultancy.DeConsultancy__DeadlinePassed.selector);
        deConsultancy.markDelivered(1, "navee");
    }

    function testMarkDeliveredRevertIfAlreadyDelivered() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        vm.prank(seller);
        vm.expectRevert(DeConsultancy.DeConsultancy__InvalidState.selector);
        deConsultancy.markDelivered(1, "navee");
    }

    // Event Testing for MarkDelivered
    function testOrderDeliverd() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 1 days);

        vm.expectEmit(true, false, false, true);
        emit DeConsultancy.OrderDelivered(1, "navee");

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");
    }

    // Test Cases for ClaimRefund
    function testClaimRefund() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days);

        uint256 buyerInitialBalance = buyer.balance;

        vm.warp(block.timestamp + 8 days);

        vm.prank(buyer);
        deConsultancy.claimRefund(1);

        DeConsultancy.Order memory order = deConsultancy.getOrder(1);

        assertEq(uint256(order.state), uint256(DeConsultancy.State.Completed));

        uint256 buyerFinalBalance = buyer.balance;
        assertEq(buyerFinalBalance, buyerInitialBalance + 1 ether);

        assertEq(address(deConsultancy).balance, 0);
    }

    function testClaimRefundIfOrderNotExist() public {
        vm.prank(buyer);
        vm.expectRevert(DeConsultancy.DeConsultancy__OrderNotExist.selector);
        deConsultancy.claimRefund(1);
    }

    function testClaimRefundNotByBuyer() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days);

        vm.warp(block.timestamp + 8 days);

        vm.prank(seller);
        vm.expectRevert(DeConsultancy.DeConsultancy__NotBuyer.selector);
        deConsultancy.claimRefund(1);
    }

    function testClaimRefundBeforeDeadline() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days);

        // vm.warp(block.timestamp + 6 days);

        vm.prank(buyer);
        vm.expectRevert(DeConsultancy.DeConsultancy__DeadlineNotPassed.selector);
        deConsultancy.claimRefund(1);
    }

    function testClaimRefundRevertIfDelivered() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 6 days);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        vm.warp(block.timestamp + 7 days);

        vm.prank(buyer);
        vm.expectRevert(DeConsultancy.DeConsultancy__InvalidState.selector);
        deConsultancy.claimRefund(1);
    }

    // Event Testing for ClaimRefund
    function testRefundClaimedEvent() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 6 days);

        vm.warp(block.timestamp + 7 days);

        vm.expectEmit(true, false, false, false);
        emit DeConsultancy.RefundClaimed(1);

        vm.prank(buyer);
        deConsultancy.claimRefund(1);
    }

    // Test Cases for approveAndRelease
    function testApproveAndRelease() public {
        uint256 buyerInitialBalance = buyer.balance;
        uint256 sellerInitialBalance = seller.balance;

        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        vm.prank(buyer);
        deConsultancy.approveAndRelease(1);

        DeConsultancy.Order memory order = deConsultancy.getOrder(1);

        assertEq(uint256(order.state), uint256(DeConsultancy.State.Completed));

        uint256 buyerFinalBalance = buyer.balance;
        uint256 sellerFinalBalance = seller.balance;

        assertEq(buyerFinalBalance, buyerInitialBalance - 1 ether);
        assertEq(sellerFinalBalance, sellerInitialBalance + 1 ether);

        assertEq(address(deConsultancy).balance, 0);
    }

    function testApproveAndReleaseRevertIfOrderNotExist() public {
        vm.prank(buyer);
        vm.expectRevert(DeConsultancy.DeConsultancy__OrderNotExist.selector);
        deConsultancy.approveAndRelease(1);
    }

    function testApproveAndReleaseButNotBuyer() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        vm.prank(seller);
        vm.expectRevert(DeConsultancy.DeConsultancy__NotBuyer.selector);
        deConsultancy.approveAndRelease(1);
    }

    function testApproveAndReleaseRevertIfNotDelivered() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days);

        vm.prank(buyer);
        vm.expectRevert(DeConsultancy.DeConsultancy__InvalidState.selector);
        deConsultancy.approveAndRelease(1);
    }

    function testApproveAndReleaseIfAleadyCompleted() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        vm.prank(buyer);
        deConsultancy.approveAndRelease(1);

        vm.prank(buyer);
        vm.expectRevert(DeConsultancy.DeConsultancy__InvalidState.selector);
        deConsultancy.approveAndRelease(1);
    }

    // Event Testing for ApproveAndRelease
    function testOrderCompletedEvent() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        vm.expectEmit(true, false, false, false);
        emit DeConsultancy.OrderCompleted(1);

        vm.prank(buyer);
        deConsultancy.approveAndRelease(1);
    }

    // Test Cases for ClaimAfterTimeout
    function testClaimAfterTimeout() public {
        uint256 buyerInitialBalance = buyer.balance;
        uint256 sellerInitialBalance = seller.balance;

        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 6 days);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        uint256 deliveryTime = deConsultancy.getDeliveryTime(1);
        vm.warp(deliveryTime + deConsultancy.TIMEOUT());

        vm.prank(seller);
        deConsultancy.claimAfterTimeout(1);

        DeConsultancy.Order memory order = deConsultancy.getOrder(1);

        assertEq(uint256(order.state), uint256(DeConsultancy.State.Completed));
        assertTrue(order.deliveryTime > 0);

        uint256 buyerFinalBalance = buyer.balance;
        uint256 sellerFinalBalance = seller.balance;

        assertEq(buyerFinalBalance, buyerInitialBalance - 1 ether);
        assertEq(sellerFinalBalance, sellerInitialBalance + 1 ether);

        assertEq(address(deConsultancy).balance, 0);
    }

    function testClaimAfterTimeoutRevertIfOrderNotExist() public {
        vm.prank(buyer);
        vm.expectRevert(DeConsultancy.DeConsultancy__OrderNotExist.selector);
        deConsultancy.claimAfterTimeout(1);
    }

    function testClaimAfterTimeoutRevertIfNotSeller() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        uint256 deliveryTime = deConsultancy.getDeliveryTime(1);
        vm.warp(deliveryTime + deConsultancy.TIMEOUT());

        vm.prank(buyer);
        vm.expectRevert(DeConsultancy.DeConsultancy__NotSeller.selector);
        deConsultancy.claimAfterTimeout(1);
    }

    function testClaimAfterTimeoutWithNotDelivered() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        uint256 deliveryTime = deConsultancy.getDeliveryTime(1);
        vm.warp(deliveryTime + deConsultancy.TIMEOUT());

        vm.prank(seller);
        deConsultancy.claimAfterTimeout(1);

        vm.prank(seller);
        vm.expectRevert(DeConsultancy.DeConsultancy__InvalidState.selector);
        deConsultancy.claimAfterTimeout(1);
    }

    function testClaimAfterTimeoutIfNotTimeOut() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        uint256 deliveryTime = deConsultancy.getDeliveryTime(1);
        vm.warp(deliveryTime + 1 days);

        vm.prank(seller);
        vm.expectRevert(DeConsultancy.DeConsultancy__TimeoutNotReached.selector);
        deConsultancy.claimAfterTimeout(1);
    }

    // Event testing for AfterTimeoutClaimed
    function testAfterTimeoutClaimedEvent() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        uint256 deliveryTime = deConsultancy.getDeliveryTime(1);
        vm.warp(deliveryTime + deConsultancy.TIMEOUT());

        vm.expectEmit(true, false, false, false);
        emit DeConsultancy.AfterTimeoutClaimed(1);

        vm.prank(seller);
        deConsultancy.claimAfterTimeout(1);
    }
}
