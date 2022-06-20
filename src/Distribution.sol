// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

struct Pool {
	address token;
	uint value;
}

contract Distribution is ERC20Snapshot, Ownable, ReentrancyGuard {
	using SafeERC20 for IERC20;

	Pool[] public pools;
	mapping(address => mapping(uint => bool)) withdrawn; // user => pid => withdrawn
	mapping(address => uint) public acknowledgedBalanceOfToken; // token => balance

	constructor() ERC20("Vault Percentage", "%") {
		_mint(msg.sender, 100e18);
	}

	// VIEW FUNCTIONS

	function getCurrentSnapshotId() public view returns (uint) {
		return _getCurrentSnapshotId();
	}

	// EXTERNAL FUNCTIONS

	function pullDistribute(address token, uint value) external nonReentrant {
		IERC20(token).safeTransferFrom(msg.sender, address(this), value);
		_skimDistribute(token);
	}

	function skimDistribute(address token) external nonReentrant {
		_skimDistribute(token);
	}

	function withdraw(uint pid) external {
		withdrawTo(msg.sender, pid);
	}

	function withdrawTo(address to, uint pid) public nonReentrant {
		_withdrawTo(to, pid);
	}

	function withdrawBatch(uint[] calldata pids) external {
		withdrawBatchTo(msg.sender, pids);
	}

	function withdrawBatchTo(address to, uint[] calldata pids) public nonReentrant {
		uint length = pids.length;
		for (uint i; i < length;) {
			_withdrawTo(to, pids[i]);
			unchecked {++i;}
		}
	}

	// INTERNAL FUNCTIONS

	function _skimDistribute(address token) internal {
		uint balance = IERC20(token).balanceOf(address(this));
		uint newBalance = balance - acknowledgedBalanceOfToken[token];
		require(newBalance != 0, "No new balance");
		acknowledgedBalanceOfToken[token] = balance;

		_createPool(token, newBalance);
	}

	function _createPool(address token, uint value) internal {
		pools.push(Pool(token, value));
		_snapshot();
	}

	function _withdrawTo(address to, uint pid) internal {
		require(!withdrawn[msg.sender][pid], "User already withdrew");
		Pool memory pool = pools[pid];

		withdrawn[msg.sender][pid] = true;
		uint _allowance = pool.value *
			balanceOfAt(msg.sender, pid) /
			totalSupplyAt(pid);

		if (_allowance > 0) {
			acknowledgedBalanceOfToken[pool.token] -= _allowance;
			IERC20(pool.token).safeTransfer(to, _allowance);
		}
	}

	// MANAGEMENT FUNCTIONS

	function withdrawEth() onlyOwner external {
		(bool success, bytes memory reason) = msg.sender.call{value: address(this).balance}("");
		require(success, string(abi.encodePacked("Transfer failed: ", reason)));
	}

	function call(address to, uint value, uint gas, bytes calldata data) onlyOwner external returns (bytes memory) {
		(bool success, bytes memory reason) = to.call{value: value, gas: gas}(data);
		require(success, string(abi.encodePacked("Call failed: ", reason)));
		return reason;
	}

	function delegatecall(address to, uint gas, bytes calldata data) onlyOwner external returns (bytes memory) {
		(bool success, bytes memory reason) = to.delegatecall{gas: gas}(data);
		require(success, string(abi.encodePacked("Delegatecall failed: ", reason)));
		return reason;
	}
}
