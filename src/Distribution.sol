// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

struct Pool {
	address token;
	uint96 timestamp;
	uint total;
	uint left;
}

contract Distribution is ERC20Snapshot, Ownable, ReentrancyGuard {
	using SafeERC20 for IERC20;

	Pool[] public pools;
	mapping(address => mapping(uint => bool)) withdrawn; // user => pid => withdrawn
	mapping(address => uint) public acknowledgedBalanceOfToken; // token => balance

	uint immutable adminRecoverTime;

	constructor(string memory vaultName, uint _adminRecoverTime) ERC20(string(abi.encodePacked(vaultName, " Vault Equity")), "%") {
		pools.push(Pool(address(0), uint96(0), 0, 0));
		adminRecoverTime = _adminRecoverTime;
		_mint(msg.sender, 100e18);
	}

	// VIEW FUNCTIONS

	function getPoolCount() public view returns (uint) {
		return _getCurrentSnapshotId();
	}

	function toClaim(address who, uint pid) public view returns (uint) {
		return pools[pid].total *
			balanceOfAt(who, pid) /
			totalSupplyAt(pid);
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
		uint poolBalance = balance - acknowledgedBalanceOfToken[token];

		require(poolBalance != 0, "No new balance");

		acknowledgedBalanceOfToken[token] = balance;
		_createPool(token, poolBalance);
	}

	function _createPool(address token, uint value) internal {
		pools.push(
			Pool({
				token: token,
				timestamp: uint96(block.timestamp),
				total: value,
				left: value
			})
		);
		_snapshot();
	}

	function _withdrawTo(address to, uint pid) internal {
		require(!withdrawn[msg.sender][pid], "Already withdrew");
		withdrawn[msg.sender][pid] = true;

		Pool storage pool = pools[pid];
		uint amount = toClaim(msg.sender, pid);

		uint left = pool.left;
		amount = amount < left ? amount : left;
		require(amount > 0, "Nothing to withdraw");

		address token = pool.token;
		acknowledgedBalanceOfToken[token] -= amount;
		pool.left = left - amount;
		IERC20(token).safeTransfer(to, amount);
	}

	// MANAGEMENT FUNCTIONS

	function adminRecover(uint lowPid, uint highPid) onlyOwner nonReentrant external {		
		// Only needs to check the last because a pool
		// with a larger pid can't have a lower timestamp
		// and timestamps are monotinocally increasing
		uint timestamp = uint(pools[highPid - 1].timestamp);
		require(
			timestamp + adminRecoverTime < block.timestamp &&
				timestamp != 0,
			"Not ready"
		);

		for (; lowPid < highPid;) {
			Pool storage pool = pools[lowPid];
			uint amount = pool.left;
			
			if (amount > 0) {
				address token = pool.token;
				pool.left = 0;
				acknowledgedBalanceOfToken[token] -= amount;
				IERC20(token).safeTransfer(msg.sender, amount);
			}
			unchecked {++lowPid;}
		}
	}

	function withdrawEth() onlyOwner external {
		(bool success, bytes memory reason) = msg.sender.call{value: address(this).balance}("");
		require(success, string(abi.encodePacked("Transfer failed: ", reason)));
	}
}
