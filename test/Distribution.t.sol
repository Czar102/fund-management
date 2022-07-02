// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "./mocks/MockERC20.sol";
import "../src/Distribution.sol";

contract DistributionTest is Test {
	Distribution public distr;
	ERC20 public erc20;

	function setUp() public {
		distr = new Distribution("tx1", 604800);
		erc20 = new MockERC20();
	}

	function testDistribute() public {
		erc20.transfer(address(distr), 1000e18);
		distr.skimDistribute(address(erc20));

		distr.transfer(address(0xdead), 10e18);
		erc20.approve(address(distr), 1000e18);
		distr.pullDistribute(address(erc20), 500e18);


		// assertEq();
	}

	function testSkimDistribute(uint value, uint firstTransfer, uint secondTransfer) public {
		vm.assume(value != 0);
		vm.assume(value <= erc20.balanceOf(address(this)));
		unchecked { // no overflow
			vm.assume(firstTransfer + secondTransfer > secondTransfer);
		}
		vm.assume(firstTransfer + secondTransfer <= erc20.balanceOf(address(this)));
		uint pid = distr.getPoolCount();

		erc20.transfer(address(distr), value);
		distr.skimDistribute(address(erc20));		

		(address token, uint96 timestamp, uint val, uint left) = distr.pools(pid);
		assertEq(val, value, "Skim distribute brought wrong pool value");
		assertTrue(token == address(erc20), "Distribute took wrong token");
	}
}
