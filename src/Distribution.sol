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

/**
 * @title Distribution
 * @author Czar102
 * @notice this contract is used to divide funds equallt to all token holders proportionally to their equity
 * @dev Only ERC20 tokens can be distributed
 */
contract Distribution is ERC20Snapshot, Ownable, ReentrancyGuard {
	using SafeERC20 for IERC20;

	/// @notice pools created, starting from index 1
	Pool[] public pools;

	/**
	 * @notice indicates if a user withdraw from a pool
	 * @dev maps user => pid => withdrawn
	 */
	mapping(address => mapping(uint => bool)) withdrawn;

	/// @notice the time after which an admin can withdraw any left tokens from any pool after its creation
	uint public immutable adminRecoveryTime;

	mapping(address => uint) private acknowledgedBalanceOfToken;

	/**
	 * @notice emitted when pool pid is created
	 * @param pid the pid of the created pool
	 * @param token the token teh pool consists of
	 * @param amount the amount of token locked
	 */
	event PoolCreated(uint indexed pid, address indexed token, uint amount);

	/**
	 * @notice emitted upon a withdrawal from pool
	 * @param pid the pool id of the pool
	 * @param from an address whose withdrawal was executed
	 * @param to an address which received withdrawn tokens
	 */
	event Withdrawal(uint indexed pid, address indexed from, address indexed to);

	/**
	 * @notice emitted when admin recovers the rest of funds from the pool
	 * @param pid the pool id from which the tokens were withdrawn
	 */
	event AdminRecover(uint indexed pid);

	/**
	 * @notice the constructor of the contract
	 * @param vaultName the name of the vault
	 * @param _adminRecoveryTime the time after which an admin can withdraw any left tokens from any pool after its creation
	 */
	constructor(string memory vaultName, uint _adminRecoveryTime) ERC20(string(abi.encodePacked(vaultName, " Vault Equity")), "%") {
		pools.push(Pool(address(0), uint96(0), 0, 0));
		adminRecoveryTime = _adminRecoveryTime;
		_mint(msg.sender, 100e18);
	}

	// VIEW FUNCTIONS

	/**
	 * @notice a getter for the number of created pools, including an empty one
	 * @return the number of existing pools
	 */
	function getPoolCount() public view returns (uint) {
		return pools.length;
	}

	/**
	 * @notice calculates how much can a user withdraw from a pool
	 * @dev note that the withdrawal call may still revert since an admin may withdraw
	 * @param who the address withdrawing tokens
	 * @param pid the pool id to withdraw from
	 * @return the amount the user can claim
	 */
	function toClaim(address who, uint pid) external view returns (uint) {
		if (withdrawn[who][pid]) return 0;

		Pool storage pool = pools[pid];
		if (pool.left == 0) return 0;
		return pool.total *
			balanceOfAt(who, pid) /
			totalSupplyAt(pid);
	}

	// EXTERNAL FUNCTIONS

	/**
	 * @notice creates a pool made of tokens pulled from the caller
	 * @notice the caller must approve the token prior to calling this function
	 * @dev it may happen that this function will create a larger pool than anticipated
	 *      because the contract may have a token inflow that hasn't been realized before
	 * @param token the token for which the pool is created
	 * @param value the value of the token to pull to create a pool
	 */
	function pullDistribute(address token, uint value) external nonReentrant {
		IERC20(token).safeTransferFrom(msg.sender, address(this), value);
		_skimDistribute(token);
	}

	/**
	 * @notice creates a pool made of the new balance of the token
	 * @param token the otken for which the pool is created
	 */
	function skimDistribute(address token) external nonReentrant {
		_skimDistribute(token);
	}

	/**
	 * @notice withdraws funds of the caller from pool pid and sends them to the caller
	 * @param pid the pool id to withdraw from
	 */
	function withdraw(uint pid) external {
		withdrawTo(msg.sender, pid);
	}

	/**
	 * @notice withdraws funds of the caller from pool pid to the specified recipient
	 * @param to the recipient of the tokens
	 * @param pid the pool id to withdraw from
	 */
	function withdrawTo(address to, uint pid) public nonReentrant {
		_withdrawTo(to, pid);
	}

	/**
	 * @notice withdraws funds of the caller from multiple pools
	 * @param pids an array of pool ids to withdraw from
	 */
	function withdrawBatch(uint[] calldata pids) external {
		withdrawBatchTo(msg.sender, pids);
	}

	/**
	 * @notice withdraws funds of the caller to a specified recipient from multiple pools
	 * @param to the recipient of the tokens
	 * @param pids an array of pool ids to withdraw from
	 */
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

		pools.push(
			Pool({
				token: token,
				timestamp: uint96(block.timestamp),
				total: poolBalance,
				left: poolBalance
			})
		);

		emit PoolCreated(_snapshot(), token, poolBalance);
	}

	function _withdrawTo(address to, uint pid) internal {
		require(!withdrawn[msg.sender][pid], "Already withdrew");
		withdrawn[msg.sender][pid] = true;

		Pool storage pool = pools[pid];

		uint left = pool.left;
		require(left != 0, "Admin withdrew");

		uint amount = pool.total *
			balanceOfAt(msg.sender, pid) /
			totalSupplyAt(pid);
		require(amount != 0, "Nothing to withdraw");

		address token = pool.token;
		acknowledgedBalanceOfToken[token] -= amount;
		pool.left = left - amount;
		IERC20(token).safeTransfer(to, amount);
		emit Withdrawal(pid, msg.sender, to);
	}

	// MANAGEMENT FUNCTIONS

	/**
	 * @notice used to recover any funds that are in a pool for longer than adminRecoveryTime
	 * @param lowPid the lower boundary of pids to recover, inclusive
	 * @param highPid the upper boundary of pids to recover, exclusive
	 */
	function adminRecover(uint lowPid, uint highPid) onlyOwner nonReentrant external {		
		// Only needs to check the last because a pool
		// with a larger pid can't have a lower timestamp
		// and timestamps are monotinocally increasing
		uint timestamp = uint(pools[highPid - 1].timestamp);
		require(
			timestamp + adminRecoveryTime <= block.timestamp &&
				timestamp != 0,
			"Not ready"
		);

		while (lowPid < highPid) {
			Pool storage pool = pools[lowPid];
			uint amount = pool.left;
			
			if (amount != 0) {
				address token = pool.token;
				pool.left = 0;
				acknowledgedBalanceOfToken[token] -= amount;
				IERC20(token).safeTransfer(msg.sender, amount);
				emit AdminRecover(lowPid);
			}
			unchecked {++lowPid;}
		}
	}

	// OVERRIDES

	function _transfer(address from, address to, uint256 amount) internal override nonReentrant {
		super._transfer(from, to, amount);
	}
}
