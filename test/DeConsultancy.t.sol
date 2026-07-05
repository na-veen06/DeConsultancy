// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

import {DeConsultancy} from "../src/DeConsultancy.sol";

contract DeConsultancyTest is Test {
    DeConsultancy deConsultancy;

    address buyer = address(1);
    address seller = address(2);
    address feeRecipient = makeAddr("feeRecipient");
    address arbiter1 = address(6);
    address arbiter2 = address(7);
    address arbiter3 = address(8);
    string requirementsCid = "QmW87n6N4v5x5x5x5x5x5x5x5x5x5x5x5x5x5x5x5x5";

    address[] arbiters = [arbiter1, arbiter2, arbiter3];

    function setUp() external {
        deConsultancy = new DeConsultancy(arbiters, feeRecipient);

        vm.deal(buyer, 10 ether);
        vm.deal(seller, 10 ether);
    }

    // Test Cases for createOrderAndPay
    function testCreateOrderAndPay() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 1 days, requirementsCid);

        assertEq(deConsultancy.orderCount(), 1);

        DeConsultancy.Order memory order = deConsultancy.getOrder(1);

        assertEq(order.buyer, buyer);
        assertEq(order.seller, seller);
        assertEq(order.price, 1 ether);
        assertEq(uint256(order.state), uint256(DeConsultancy.State.Paid));

        // assertTrue(order.deadline > block.timestamp);
        // assertEq(order.deadline, block.timestamp + 1 days);
    }

    function testCreateOrderAndPayWithIncorrectPrice() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        vm.expectRevert(DeConsultancy.DeConsultancy__IncorrectPrice.selector);
        deConsultancy.createOrderAndPay{value: 0.5 ether}(seller, 1 days, requirementsCid);

        assertEq(deConsultancy.orderCount(), 0);
    }

    function testCreateOrderAndPayWithNoPriceSet() public {
        vm.prank(buyer);
        vm.expectRevert(DeConsultancy.DeConsultancy__PriceNotSet.selector);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 1 days, requirementsCid);

        assertEq(deConsultancy.orderCount(), 0);
    }

    function testCreateOrderAndPayWithSameSellerAndBuyer() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(seller);
        vm.expectRevert(DeConsultancy.DeConsultancy__BuyerSellerSame.selector);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 1 days, requirementsCid);

        assertEq(deConsultancy.orderCount(), 0);
    }

    function testCreateOrderAndPayWithInvalidDuration() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        vm.expectRevert(DeConsultancy.DeConsultancy__InvalidDuration.selector);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 0 days, requirementsCid);

        assertEq(deConsultancy.orderCount(), 0);
    }

    function testCreateOrderAndPayWithDurationTooLong() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        vm.expectRevert(DeConsultancy.DeConsultancy__DurationTooLong.selector);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 31 days, requirementsCid);

        assertEq(deConsultancy.orderCount(), 0);
    }

    // Event Testing for CreateOrderAndPay
    function testOrderCreatedEvent() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.expectEmit(true, true, false, true);
        emit DeConsultancy.OrderCreated(1, buyer, seller, 1 ether, 1 days, requirementsCid);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 1 days, requirementsCid);
    }

    // Test Cases for CancelUnacceptedOrder
    function testCancelUnacceptedOrder() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        uint256 buyerInitialBalance = buyer.balance;

        vm.warp(block.timestamp + deConsultancy.ACCEPT_TIMEOUT());

        vm.prank(buyer);
        deConsultancy.cancelUnacceptedOrder(1);

        assertEq(uint256(deConsultancy.getOrderState(1)), uint256(DeConsultancy.State.Completed));

        uint256 buyerFinalBalance = buyer.balance;
        assertEq(buyerFinalBalance, buyerInitialBalance + 1 ether);

        assertEq(address(deConsultancy).balance, 0);
    }

    function testCancelUnacceptedOrderRevertsIfOrderNotExist() public {
        vm.expectRevert(DeConsultancy.DeConsultancy__OrderNotExist.selector);
        vm.prank(buyer);
        deConsultancy.cancelUnacceptedOrder(999);
    }

    function testCancelUnacceptedOrderRevertsIfTimeoutNotReached() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);

        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 5 days, requirementsCid);

        vm.expectRevert(DeConsultancy.DeConsultancy__AcceptTimeoutNotReached.selector);

        vm.prank(buyer);

        deConsultancy.cancelUnacceptedOrder(1);
    }

    function testCancelUnacceptedOrderRevertsIfNotBuyer() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);

        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 5 days, requirementsCid);

        vm.warp(block.timestamp + deConsultancy.ACCEPT_TIMEOUT());

        vm.expectRevert(DeConsultancy.DeConsultancy__NotBuyer.selector);

        vm.prank(seller);

        deConsultancy.cancelUnacceptedOrder(1);
    }

    function testCancelUnacceptedOrderRevertsIfOrderAccepted() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);

        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 5 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.warp(block.timestamp + deConsultancy.ACCEPT_TIMEOUT());

        vm.expectRevert(DeConsultancy.DeConsultancy__InvalidState.selector);

        vm.prank(buyer);

        deConsultancy.cancelUnacceptedOrder(1);
    }

    // Event Testing for CancelUnacceptedOrder
    function testCancelUnacceptedOrderEvent() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.warp(block.timestamp + deConsultancy.ACCEPT_TIMEOUT());

        vm.expectEmit(true, true, false, true);
        emit DeConsultancy.OrderCancelled(1);

        vm.prank(buyer);
        deConsultancy.cancelUnacceptedOrder(1);
    }

    // Test Cases for AcceptOrder
    function testSellerCanAcceptOrder() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 5 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        assertEq(uint256(deConsultancy.getOrderState(1)), uint256(DeConsultancy.State.InProgress));

        DeConsultancy.Order memory order = deConsultancy.getOrder(1);

        assertEq(order.acceptedAt, block.timestamp);

        assertEq(order.deadline, block.timestamp + 5 days);
    }

    function testAcceptOrderRevertsIfOrderNotExist() public {
        vm.expectRevert(DeConsultancy.DeConsultancy__OrderNotExist.selector);

        vm.prank(seller);

        deConsultancy.acceptOrder(999);
    }

    function testAcceptOrderRevertsIfNotSeller() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 5 days, requirementsCid);

        vm.expectRevert(DeConsultancy.DeConsultancy__NotSeller.selector);
        vm.prank(buyer);
        deConsultancy.acceptOrder(1);
    }

    function testAcceptOrderRevertsIfAlreadyAccepted() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 5 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.expectRevert(DeConsultancy.DeConsultancy__InvalidState.selector);

        vm.prank(seller);

        deConsultancy.acceptOrder(1);
    }

    //Event Testing for AcceptOrder
    function testOrderAcceptedEvent() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 5 days, requirementsCid);

        vm.expectEmit(true, false, false, true);
        emit DeConsultancy.OrderAccepted(1, msg.sender);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);
    }

    // Test Cases for markDelivered
    function testMarkDelivered() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

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
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(buyer);
        vm.expectRevert(DeConsultancy.DeConsultancy__NotSeller.selector);
        deConsultancy.markDelivered(1, "navee");
    }

    function testMarkDeliveredWithDeadlinePassed() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 6 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.warp(block.timestamp + 7 days);

        vm.prank(seller);
        vm.expectRevert(DeConsultancy.DeConsultancy__DeadlinePassed.selector);
        deConsultancy.markDelivered(1, "navee");
    }

    function testMarkDeliveredRevertIfAlreadyDelivered() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

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
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 1 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

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
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

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
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.warp(block.timestamp + 8 days);

        vm.prank(seller);
        vm.expectRevert(DeConsultancy.DeConsultancy__NotBuyer.selector);
        deConsultancy.claimRefund(1);
    }

    function testClaimRefundBeforeDeadline() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);
        // vm.warp(block.timestamp + 6 days);

        vm.prank(buyer);
        vm.expectRevert(DeConsultancy.DeConsultancy__DeadlineNotPassed.selector);
        deConsultancy.claimRefund(1);
    }

    function testClaimRefundRevertIfDelivered() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 6 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

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
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 6 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

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
        uint256 feeRecipientInitialBalance = feeRecipient.balance;

        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        uint256 fee = (1 ether * deConsultancy.getFeePercentage()) / 100;
        uint256 sellerAmount = 1 ether - fee;

        vm.prank(buyer);
        deConsultancy.approveAndRelease(1);

        DeConsultancy.Order memory order = deConsultancy.getOrder(1);

        assertEq(uint256(order.state), uint256(DeConsultancy.State.Completed));

        uint256 buyerFinalBalance = buyer.balance;
        uint256 sellerFinalBalance = seller.balance;
        uint256 feeRecipientFinalBalance = feeRecipient.balance;

        assertEq(buyerFinalBalance, buyerInitialBalance - 1 ether);
        assertEq(sellerFinalBalance, sellerInitialBalance + sellerAmount);
        assertEq(feeRecipientFinalBalance, feeRecipientInitialBalance + fee);

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
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

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
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(buyer);
        vm.expectRevert(DeConsultancy.DeConsultancy__InvalidState.selector);
        deConsultancy.approveAndRelease(1);
    }

    function testApproveAndReleaseIfAleadyCompleted() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

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
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

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
        uint256 feeRecipientInitialBalance = feeRecipient.balance;

        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 6 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        uint256 deliveryTime = deConsultancy.getDeliveryTime(1);
        vm.warp(deliveryTime + deConsultancy.TIMEOUT());

        uint256 fee = (1 ether * deConsultancy.getFeePercentage()) / 100;
        uint256 sellerAmount = 1 ether - fee;

        vm.prank(seller);
        deConsultancy.claimAfterTimeout(1);

        DeConsultancy.Order memory order = deConsultancy.getOrder(1);

        assertEq(uint256(order.state), uint256(DeConsultancy.State.Completed));
        assertTrue(order.deliveryTime > 0);

        uint256 buyerFinalBalance = buyer.balance;
        uint256 sellerFinalBalance = seller.balance;
        uint256 feeRecipientFinalBalance = feeRecipient.balance;

        assertEq(buyerFinalBalance, buyerInitialBalance - 1 ether);
        assertEq(sellerFinalBalance, sellerInitialBalance + sellerAmount);
        assertEq(feeRecipientFinalBalance, feeRecipientInitialBalance + fee);

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
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

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
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

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
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

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
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        uint256 deliveryTime = deConsultancy.getDeliveryTime(1);
        vm.warp(deliveryTime + deConsultancy.TIMEOUT());

        vm.expectEmit(true, false, false, false);
        emit DeConsultancy.AfterTimeoutClaimed(1);

        vm.prank(seller);
        deConsultancy.claimAfterTimeout(1);
    }

    // Test Cases for RaiseDispute
    function testRaiseDispute() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        vm.prank(seller);
        deConsultancy.raiseDispute(1);

        DeConsultancy.Order memory order = deConsultancy.getOrder(1);

        assertEq(uint256(order.state), uint256(DeConsultancy.State.Disputed));
        assertEq(order.disputed, true);
    }

    function testRaiseDisputeRevertIfOrderNotExist() public {
        vm.prank(buyer);
        vm.expectRevert(DeConsultancy.DeConsultancy__OrderNotExist.selector);
        deConsultancy.raiseDispute(1);
    }

    function testRaiseDisputeRevertIfNotAuthorized() public {
        address attacker = address(3);

        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        vm.prank(attacker);
        vm.expectRevert(DeConsultancy.DeConsultancy__Unauthorized.selector);
        deConsultancy.raiseDispute(1);
    }

    function testRaiseDisputeRevertIfNotDelivered() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(buyer);
        vm.expectRevert(DeConsultancy.DeConsultancy__InvalidState.selector);
        deConsultancy.raiseDispute(1);
    }

    function testRaiseDisputeRevertIfAlreadyDisputed() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        vm.prank(buyer);
        deConsultancy.raiseDispute(1);

        vm.prank(seller);
        vm.expectRevert(DeConsultancy.DeConsultancy__AlreadyDisputed.selector);
        deConsultancy.raiseDispute(1);
    }

    // Event Testing for RaiseDispute
    function testDisputeRaisedEvent() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        vm.expectEmit(true, false, false, false);
        emit DeConsultancy.DisputeRaised(1);

        vm.prank(buyer);
        deConsultancy.raiseDispute(1);
    }

    // Test for VoteOnDispute
    function testVoteOnDisputeSellerVote() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        vm.prank(buyer);
        deConsultancy.raiseDispute(1);

        vm.prank(arbiter1);
        deConsultancy.voteOnDispute(1, true);

        assertEq(deConsultancy.sellerVotes(1), 1);
        assertEq(deConsultancy.buyerVotes(1), 0);
    }

    function testVoteOnDisputeBuyerVote() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        vm.prank(buyer);
        deConsultancy.raiseDispute(1);

        vm.prank(arbiter1);
        deConsultancy.voteOnDispute(1, false);

        assertEq(deConsultancy.sellerVotes(1), 0);
        assertEq(deConsultancy.buyerVotes(1), 1);
    }

    function testResolveDisputeRevertIfOrderNotExist() public {
        vm.prank(arbiter1);
        vm.expectRevert(DeConsultancy.DeConsultancy__OrderNotExist.selector);
        deConsultancy.voteOnDispute(1, true);
    }

    function testResolveDisputeRevertIfNotArbiter() public {
        address attacker = address(67);

        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        vm.prank(buyer);
        deConsultancy.raiseDispute(1);

        vm.prank(attacker);
        vm.expectRevert(DeConsultancy.DeConsultancy__NotArbiter.selector);
        deConsultancy.voteOnDispute(1, false);
    }

    function testResolveDisputeRevertIfNotDisputed() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        vm.prank(arbiter1);
        vm.expectRevert(DeConsultancy.DeConsultancy__InvalidState.selector);
        deConsultancy.voteOnDispute(1, true);
    }

    function testResolveDisputeRevertIfAlreadyVoted() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        vm.prank(buyer);
        deConsultancy.raiseDispute(1);

        vm.prank(arbiter1);
        deConsultancy.voteOnDispute(1, true);

        vm.prank(arbiter1);
        vm.expectRevert(DeConsultancy.DeConsultancy__AlreadyVoted.selector);
        deConsultancy.voteOnDispute(1, true);
    }

    function testVoteOnDisputeRevertIfAlreadyResolved() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        vm.prank(buyer);
        deConsultancy.raiseDispute(1);

        vm.prank(arbiter1);
        deConsultancy.voteOnDispute(1, true);

        vm.prank(arbiter2);
        deConsultancy.voteOnDispute(1, true);

        vm.prank(arbiter3);
        vm.expectRevert(DeConsultancy.DeConsultancy__AlreadyResolved.selector);
        deConsultancy.voteOnDispute(1, true);
    }

    function testVoteTriggersResolutionSellerWins() public {
        uint256 sellerInitialBalance = seller.balance;
        uint256 feeRecipientInitialBalance = feeRecipient.balance;

        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "hash");

        uint256 fee = (1 ether * deConsultancy.getFeePercentage()) / 100;
        uint256 sellerAmount = 1 ether - fee;

        vm.prank(buyer);
        deConsultancy.raiseDispute(1);

        vm.prank(arbiter1);
        deConsultancy.voteOnDispute(1, true);

        assertEq(uint256(deConsultancy.getOrderState(1)), uint256(DeConsultancy.State.Disputed));

        vm.prank(arbiter2);
        deConsultancy.voteOnDispute(1, true);

        assertEq(uint256(deConsultancy.getOrderState(1)), uint256(DeConsultancy.State.Completed));
        assertEq(seller.balance, sellerInitialBalance + sellerAmount);
        assertEq(feeRecipient.balance, feeRecipientInitialBalance + fee);
        assertEq(address(deConsultancy).balance, 0);
    }

    function testVoteTriggersResolutionBuyerWins() public {
        uint256 buyerInitialBalance = buyer.balance;

        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "hash");

        vm.prank(buyer);
        deConsultancy.raiseDispute(1);

        vm.prank(arbiter1);
        deConsultancy.voteOnDispute(1, false);

        assertEq(uint256(deConsultancy.getOrderState(1)), uint256(DeConsultancy.State.Disputed));

        vm.prank(arbiter2);
        deConsultancy.voteOnDispute(1, false);

        assertEq(uint256(deConsultancy.getOrderState(1)), uint256(DeConsultancy.State.Completed));
        assertEq(buyer.balance, buyerInitialBalance);
        assertEq(address(deConsultancy).balance, 0);
    }

    function testNoMajorityNoResolution() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "hash");

        vm.prank(buyer);
        deConsultancy.raiseDispute(1);

        vm.prank(arbiter1);
        deConsultancy.voteOnDispute(1, true);

        assertEq(uint256(deConsultancy.getOrderState(1)), uint256(DeConsultancy.State.Disputed));
    }

    function testMixedVotesBuyerWins() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "hash");

        vm.prank(buyer);
        deConsultancy.raiseDispute(1);

        vm.prank(arbiter1);
        deConsultancy.voteOnDispute(1, true);

        vm.prank(arbiter2);
        deConsultancy.voteOnDispute(1, false);

        assertEq(uint256(deConsultancy.getOrderState(1)), uint256(DeConsultancy.State.Disputed));

        vm.prank(arbiter3);
        deConsultancy.voteOnDispute(1, false);

        assertEq(uint256(deConsultancy.getOrderState(1)), uint256(DeConsultancy.State.Completed));
    }

    function testMixedVotesSellerWins() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "hash");

        vm.prank(buyer);
        deConsultancy.raiseDispute(1);

        vm.prank(arbiter1);
        deConsultancy.voteOnDispute(1, true);

        vm.prank(arbiter2);
        deConsultancy.voteOnDispute(1, false);

        assertEq(uint256(deConsultancy.getOrderState(1)), uint256(DeConsultancy.State.Disputed));

        vm.prank(arbiter3);
        deConsultancy.voteOnDispute(1, true);

        assertEq(uint256(deConsultancy.getOrderState(1)), uint256(DeConsultancy.State.Completed));
    }

    // Event Testing for VoteOnDispute
    function testVoteOnDisputeEvent() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "hash");

        vm.prank(buyer);
        deConsultancy.raiseDispute(1);

        vm.expectEmit(true, true, false, true);
        emit DeConsultancy.Voted(1, arbiter1, true);

        vm.prank(arbiter1);
        deConsultancy.voteOnDispute(1, true);
    }

    function testDisputeResolvedEventViaVoting() public {
        vm.prank(seller);
        deConsultancy.setPrice(1 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 1 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "hash");

        vm.prank(buyer);
        deConsultancy.raiseDispute(1);

        vm.prank(arbiter1);
        deConsultancy.voteOnDispute(1, true);

        vm.expectEmit(true, false, false, true);
        emit DeConsultancy.DisputeResolved(1, seller);

        vm.prank(arbiter2);
        deConsultancy.voteOnDispute(1, true);
    }

    // Test for ResolveSplit
    function testResolveSplit() public {
        uint256 sellerInitialBalance = seller.balance;
        uint256 feeRecipientInitialBalance = feeRecipient.balance;

        vm.prank(seller);
        deConsultancy.setPrice(7 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 7 ether}(seller, 7 days, requirementsCid);

        uint256 buyerBalanceAfterPayment = buyer.balance;

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        vm.prank(buyer);
        deConsultancy.raiseDispute(1);

        uint256 fee = (6 ether * deConsultancy.getFeePercentage()) / 100;
        uint256 sellerAmount = 6 ether - fee;

        vm.prank(arbiter1);
        deConsultancy.resolveSplit(1, 6 ether);

        DeConsultancy.Order memory order = deConsultancy.getOrder(1);

        assertEq(uint256(order.state), uint256(DeConsultancy.State.Completed));
        assertEq(seller.balance, sellerInitialBalance + sellerAmount);
        assertEq(buyer.balance, buyerBalanceAfterPayment + 1 ether);
        assertEq(feeRecipient.balance, feeRecipientInitialBalance + fee);
        assertEq(address(deConsultancy).balance, 0);
    }

    function testResolveSplitRevertIfOrderNotExist() public {
        vm.prank(arbiter1);
        vm.expectRevert(DeConsultancy.DeConsultancy__OrderNotExist.selector);
        deConsultancy.resolveSplit(1, 1 ether);
    }

    function testResolveSplitRevertIfSellerAmountIsTooHigh() public {
        vm.prank(seller);
        deConsultancy.setPrice(7 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 7 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        vm.prank(buyer);
        deConsultancy.raiseDispute(1);

        vm.prank(arbiter2);
        vm.expectRevert(DeConsultancy.DeConsultancy__IncorrectPrice.selector);
        deConsultancy.resolveSplit(1, 9 ether);
    }

    function testResolveSplitRevertIfNotArbiter() public {
        address attacker = address(3);

        vm.prank(seller);
        deConsultancy.setPrice(7 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 7 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        vm.prank(buyer);
        deConsultancy.raiseDispute(1);

        vm.prank(attacker);
        vm.expectRevert(DeConsultancy.DeConsultancy__NotArbiter.selector);
        deConsultancy.resolveSplit(1, 6 ether);
    }

    function testResolveSplitRevertIfNotDisputed() public {
        vm.prank(seller);
        deConsultancy.setPrice(7 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 7 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        vm.prank(arbiter2);
        vm.expectRevert(DeConsultancy.DeConsultancy__InvalidState.selector);
        deConsultancy.resolveSplit(1, 6 ether);
    }

    function testResolveSplitFullSeller() public {
        uint256 feeRecipientInitialBalance = feeRecipient.balance;

        vm.prank(seller);
        deConsultancy.setPrice(7 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 7 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        vm.prank(buyer);
        deConsultancy.raiseDispute(1);

        uint256 fee = (7 ether * deConsultancy.getFeePercentage()) / 100;
        uint256 sellerAmount = 7 ether - fee;

        uint256 sellerInitialBalance = seller.balance;

        vm.prank(arbiter2);
        deConsultancy.resolveSplit(1, 7 ether);

        assertEq(seller.balance, sellerInitialBalance + sellerAmount);
        assertEq(feeRecipient.balance, feeRecipientInitialBalance + fee);
    }

    function testResolveSplitFullBuyer() public {
        vm.prank(seller);
        deConsultancy.setPrice(7 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 7 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        vm.prank(buyer);
        deConsultancy.raiseDispute(1);

        uint256 buyerInitialBalance = buyer.balance;

        vm.prank(arbiter3);
        deConsultancy.resolveSplit(1, 0);

        assertEq(buyer.balance, buyerInitialBalance + 7 ether);
    }

    // Event Testing for ResolveSplit
    function testDisputeResolvedEventViaSplit() public {
        vm.prank(seller);
        deConsultancy.setPrice(7 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 7 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        uint256 buyerAmount = 1 ether;
        uint256 fee = (6 ether * deConsultancy.getFeePercentage()) / 100;
        uint256 sellerAmount = 6 ether - fee;

        vm.prank(buyer);
        deConsultancy.raiseDispute(1);

        vm.expectEmit(true, false, false, true);
        emit DeConsultancy.DisputeResolvedSplit(1, sellerAmount, buyerAmount);

        vm.prank(arbiter3);
        deConsultancy.resolveSplit(1, 6 ether);
    }

    // Test Cases for ResolveAfterDisputeTimeout
    function testResolveAfterDisputeTimeout() public {
        uint256 sellerInitialBalance = seller.balance;
        uint256 feeRecipientInitialBalance = feeRecipient.balance;

        vm.prank(seller);
        deConsultancy.setPrice(7 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 7 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        vm.prank(buyer);
        deConsultancy.raiseDispute(1);

        uint256 fee = (7 ether * deConsultancy.getFeePercentage()) / 100;
        uint256 sellerAmount = 7 ether - fee;

        vm.warp(block.timestamp + deConsultancy.DISPUTE_TIMEOUT() + 1);

        deConsultancy.resolveAfterDisputeTimeout(1);

        DeConsultancy.Order memory order = deConsultancy.getOrder(1);

        assertEq(uint256(order.state), uint256(DeConsultancy.State.Completed));
        assertEq(seller.balance, sellerInitialBalance + sellerAmount);
        assertEq(feeRecipient.balance, feeRecipientInitialBalance + fee);
        assertEq(address(deConsultancy).balance, 0);
    }

    function testResolveAfterDisputeTimeoutRevertIfOrderNotExist() public {
        vm.expectRevert(DeConsultancy.DeConsultancy__OrderNotExist.selector);
        deConsultancy.resolveAfterDisputeTimeout(1);
    }

    function testResolveAfterDisputeTimeoutRevertIfNotDisputed() public {
        vm.prank(seller);
        deConsultancy.setPrice(7 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 7 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        vm.expectRevert(DeConsultancy.DeConsultancy__InvalidState.selector);
        deConsultancy.resolveAfterDisputeTimeout(1);
    }

    function testResolveAfterDisputeTimeoutRevertIfTimeNotPassed() public {
        vm.prank(seller);
        deConsultancy.setPrice(7 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 7 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        vm.prank(buyer);
        deConsultancy.raiseDispute(1);

        vm.warp(block.timestamp + 1 days);

        vm.expectRevert(DeConsultancy.DeConsultancy__TimeoutNotReached.selector);
        deConsultancy.resolveAfterDisputeTimeout(1);
    }

    function testResolveAfterDisputeTimeoutIfalreadyResolved() public {
        vm.prank(seller);
        deConsultancy.setPrice(7 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 7 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        vm.prank(buyer);
        deConsultancy.raiseDispute(1);

        vm.warp(block.timestamp + deConsultancy.DISPUTE_TIMEOUT() + 1);

        deConsultancy.resolveAfterDisputeTimeout(1);

        vm.expectRevert(DeConsultancy.DeConsultancy__AlreadyResolved.selector);
        deConsultancy.resolveAfterDisputeTimeout(1);
    }

    // Event Testing for DisputeResolved via Timeout
    function testDisputeResolvedEventViaTimeout() public {
        vm.prank(seller);
        deConsultancy.setPrice(7 ether);

        vm.prank(buyer);
        deConsultancy.createOrderAndPay{value: 7 ether}(seller, 7 days, requirementsCid);

        vm.prank(seller);
        deConsultancy.acceptOrder(1);

        vm.prank(seller);
        deConsultancy.markDelivered(1, "navee");

        vm.prank(buyer);
        deConsultancy.raiseDispute(1);

        vm.warp(block.timestamp + deConsultancy.DISPUTE_TIMEOUT() + 1);

        vm.expectEmit(true, false, false, true);
        emit DeConsultancy.DisputeResolved(1, seller);
        deConsultancy.resolveAfterDisputeTimeout(1);
    }
}
