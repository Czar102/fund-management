// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

contract ForceETHTransfer {
	constructor(address to) payable {
		require(msg.value != 0, "transferring zero value");
		selfdestruct(payable(to));
	}
}
