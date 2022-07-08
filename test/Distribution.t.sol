// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "./mocks/MockERC20.sol";
import "../src/Distribution.sol";

uint constant RECOVER_TIME = 604800;

contract DistributionTest is Test {
	Distribution public distr;
	ERC20 public erc20;

	function setUp() public {
		distr = new Distribution("tx1", RECOVER_TIME);
		erc20 = new MockERC20();
	}

	/// could have used `deal`, but that wouldn't be fun
	function forceEtherTransfer(address to, uint amount) internal {
		assembly {
			mstore(0, or(0x730000000000000000000000000000000000000000ff, shl(8, to)))
			pop(create(amount, 10, 22))
		}
	}

	function testDistribute() public {
		erc20.transfer(address(distr), 1000e18);
		distr.skimDistribute(address(erc20));

		distr.transfer(address(0xdead), 10e18);
		erc20.approve(address(distr), 1000e18);
		distr.pullDistribute(address(erc20), 500e18);

		// skimDistribute parameters
		(address token, uint96 timestamp, uint val, uint left) = distr.pools(1);
		assertEq(token, address(erc20), "wrong token");
		assertEq(uint(timestamp), block.timestamp, "wrong timestamp");
		assertEq(val, 1000e18, "wrong value");
		assertEq(left, val, "value leak");
		assertEq(distr.toClaim(address(this), 1), val, "wrong toClaim value");

		// pullDistribute parameters
		(token, timestamp, val, left) = distr.pools(2);
		assertEq(token, address(erc20), "wrong token");
		assertEq(uint(timestamp), block.timestamp, "wrong timestamp");
		assertEq(val, 500e18, "wrong value");
		assertEq(left, val, "value leak");
		assertEq(distr.toClaim(address(this), 2), val * 9 / 10, "wrong toClaim value");

		{
			uint valueBefore = erc20.balanceOf(address(this));
			distr.withdraw(1);

			vm.expectRevert("Already withdrew");
			distr.withdraw(1);

			uint valueAfter = erc20.balanceOf(address(this));
			assertEq(valueAfter - valueBefore, 1000e18);

			(token, timestamp, val, left) = distr.pools(1);

			assertEq(left, 0, "left more than 0");
			assertEq(distr.toClaim(address(this), 1), 0, "wrong toClaim value");
		}

		{
			uint valueBefore = erc20.balanceOf(address(this));
			distr.withdraw(2);

			vm.expectRevert("Already withdrew");
			distr.withdraw(2);

			uint valueAfter = erc20.balanceOf(address(this));
			assertEq(valueAfter - valueBefore, 450e18);

			(token, timestamp, val, left) = distr.pools(2);

			assertEq(left, 50e18, "left wrong value");
			assertEq(distr.toClaim(address(0xdead), 2), 50e18, "wrong toClaim value");
			assertEq(distr.toClaim(address(this), 2), 0, "wrong toClaim value");
		}

		{
			uint valueBefore = erc20.balanceOf(address(0xdead));

			vm.startPrank(address(0xdead));
			distr.withdraw(2);
			vm.expectRevert("Already withdrew");
			distr.withdraw(2);
			vm.stopPrank();

			uint valueAfter = erc20.balanceOf(address(0xdead));
			assertEq(valueAfter - valueBefore, 50e18);

			(token, timestamp, val, left) = distr.pools(2);

			assertEq(left, 0, "left wrong value");
			assertEq(distr.toClaim(address(0xdead), 2), 0, "wrong toClaim value");
		}
	}

	function testSkimDistribute(uint value, uint firstTransfer, uint secondTransfer) public {
		vm.assume(value != 0);
		vm.assume(value <= erc20.balanceOf(address(this)));
		unchecked { // no overflow
			vm.assume(firstTransfer + secondTransfer > secondTransfer);
		}
		vm.assume(firstTransfer + secondTransfer <= erc20.balanceOf(address(this)));

		erc20.transfer(address(distr), value);
		distr.skimDistribute(address(erc20));		

		uint pid = distr.getPoolCount() - 1;
		(address token,, uint val,) = distr.pools(pid);
		assertEq(val, value, "Skim distribute brought wrong pool value");
		assertEq(token, address(erc20), "Distribute took wrong token");
	}

	function testBatchWithdraw() public {
		address a1 = address(0x01);
		address a2 = address(0x02);

		distr.transfer(a1, 25e18);
		distr.transfer(a2, 40e18);

		erc20.transfer(address(distr), 100);
		distr.skimDistribute(address(erc20));
		erc20.transfer(address(distr), 1000);
		distr.skimDistribute(address(erc20));

		distr.withdrawTo(a1, 1);
		assertEq(erc20.balanceOf(a1), 35);

		uint[] memory pids = new uint[](2);
		pids[0] = 1;
		pids[1] = 2;

		vm.prank(a1);
		distr.withdrawBatchTo(a2, pids);
		assertEq(erc20.balanceOf(a2), 250 + 25);

		vm.prank(a2);
		distr.withdrawBatch(pids);
		assertEq(erc20.balanceOf(a2), 250 + 25 + 40 + 400);
	}

	function testETHRescue() public {
		vm.deal(address(this), 1e18);
		vm.expectRevert();
		(bool failure,) = address(distr).call{value: 1e18}("");
		assertTrue(failure, "call was successful");

		forceEtherTransfer(address(distr), 1e18);

		assertEq(address(distr).balance, 1e18, "Transfer failure");

		distr.withdrawEth();

		assertEq(address(this).balance, 1e18, "Wring Ether value");
	}

	receive() external payable {}
}
