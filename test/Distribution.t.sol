// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "./mocks/MockERC20.sol";
import "../src/Distribution.sol";

contract DistributionTest is Test {
	Distribution public distr;
	ERC20 public erc20;

	function setUp() public {
		distr = new Distribution();
		erc20 = new MockERC20();
	}

	function testSkimDistribute(uint value) public {
		vm.assume(value != 0);
		vm.assume(value < erc20.balanceOf(address(this)));
		uint pid = distr.getCurrentSnapshotId();

		erc20.transfer(address(distr), value);
		distr.skimDistribute(address(erc20));		

		(address token, uint val) = distr.pools(pid);
		assertEq(val, value, "Skim distribute brought wrong pool value");
		assertEq(uint(uint160(token)), uint(uint160(address(erc20))), "Distribute took wrong token");
	}
}
