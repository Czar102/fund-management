// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "./mocks/MockERC20.sol";
import "../src/TrustlessPayment.sol";

contract TrustlessPaymentTest is Test {
	TrustlessPayment public tp;
	ERC20 public erc20;

	address ESCROW = vm.addr(uint256(keccak256("ESCROW")));
	address PAYER = vm.addr(uint256(keccak256("PAYER")));
	address RECEIVER = vm.addr(uint256(keccak256("RECEIVER")));

	uint constant amount = 1337e18;

	function setUp() public {
		erc20 = new MockERC20();
		tp = new TrustlessPayment(ESCROW, PAYER, RECEIVER, address(erc20), amount);
		erc20.transfer(ESCROW, 2 * amount);
	}

	function testExecute() public {
		vm.prank(ESCROW);
		erc20.approve(address(tp), 2 * amount);

		vm.prank(PAYER);
		erc20.approve(address(tp), 2 * amount);


		uint balanceOfEscrowBefore = erc20.balanceOf(ESCROW);
		uint balanceOfReceiverBefore = erc20.balanceOf(RECEIVER);		
		tp.execute();
		assertEq(erc20.balanceOf(RECEIVER), balanceOfReceiverBefore + amount);
		assertEq(erc20.balanceOf(ESCROW), balanceOfEscrowBefore - amount);

		vm.expectRevert();
		tp.execute();
	}
}
