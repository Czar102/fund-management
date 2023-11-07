// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title TrustlessPayment
 * @author Czar102
 * @notice trustlessly transfers funds from escrow to the receiver
 */
contract TrustlessPayment {
	using SafeERC20 for IERC20;

	address public immutable escrow;
	address public immutable payer;
	address public immutable receiver;

	IERC20 public immutable token;
	uint public immutable amount;

	bool public executed;

	constructor(address _escrow, address _payer, address _receiver, address _token, uint _amount) {
		escrow = _escrow;
		payer = _payer;
		receiver = _receiver;
		token = IERC20(_token);
		amount = _amount;
	}

	/**
	 * @notice executes the transaction
	 * @dev invokable only once
	 */
	function execute() public {
		require(!executed, "Already executed");
		executed = true;

		token.safeTransferFrom(escrow, payer, amount);
		token.safeTransferFrom(payer, receiver, amount);
	}
}
