// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IFlashLoanCallback {
    /// @dev Callback function to receive the result of the flash loan
    /// @param fee The fee of the flash loan
    function flashLoanCallback(uint fee) payable external;
}

contract Coprocessor {
    address payable public immutable coprocessor;

    uint public id = 0; // Last job id (0 = no jobs yet)

    mapping(uint => string) public jobs;

    error OnlyCoprocessor();
    error WrongBalance();

    constructor(address _coprocessor) {
        coprocessor = payable(_coprocessor);
    }

    event Bridge(
        uint indexed chainId,
        address indexed receiver,
        uint indexed valueIn,
        uint coprocessorBalance
    );

    /// ===== BRIDGE  =====

    /// @dev Bridge the value to another chain with optional call to receiver contract and optional callback to the source chain
    /// @param chainId The chain id to bridge to. Negative values for non-EVM chains
    /// @param receiver The receiver address on the other chain
    function bridge(uint chainId, address receiver)
    external payable  {
        coprocessor.transfer(msg.value);
        emit Bridge(chainId, receiver, msg.value, coprocessor.balance);
    }



    receive() external payable {} // To receive flash loans back

    function flashLoan(uint amount) external {
        uint balance = address(this).balance;
        payable(msg.sender).transfer(amount);
        uint fee = amount >> 10; // Same as amount / 1024 or amount * 0.09765625%
        IFlashLoanCallback(msg.sender).flashLoanCallback(fee);
        if (address(this).balance < (balance + fee)) revert WrongBalance();
    }


    // ===== JOB =====

    function getResult(uint _job_id) public view returns (string memory) {
        return jobs[_job_id];
    }

    function callback(string calldata _result, uint256 _job_id) public {
        if (msg.sender != coprocessor) revert OnlyCoprocessor();
        jobs[_job_id] = _result;
    }
}
