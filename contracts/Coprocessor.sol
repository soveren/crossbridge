// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IBridgeCallback {
    /// @dev Callback function to receive the result of the bridge call
    /// @notice Function may receive change (unused value) back
    /// @param jobId The id of the job
    /// @param success The success status of the call on the destination chain
    /// @param result The result of the call on the destination chain (when data is provided in the bridge call)
    function bridgeCallback(uint jobId, bool success, bytes calldata result) payable external;
}

interface IFlashLoanCallback {
    /// @dev Callback function to receive the result of the flash loan
    /// @param fee The fee of the flash loan
    function flashLoanCallback(uint fee) payable external;
}

interface IBridge {
    function coprocessor() external view returns (address payable);
    function bridge(int chainId, address receiver, uint transferValue, bytes calldata dataWithSelector, uint callbackGasValue) payable external returns (uint jobId);

}

contract Coprocessor is IBridge {
    address payable public immutable coprocessor;
    uint public immutable minValue = 0.001 ether;

    uint public id = 0;

    mapping(uint => string) public jobs;

    error ValueTooSmall();
    error OnlyCoprocessor();
    error WrongBalance();

    constructor(address _coprocessor) {
        coprocessor = payable(_coprocessor);
    }

    event NewJob(uint indexed job_id);

    event Bridge(
        uint indexed jobId,
        uint coprocessorBalance,
        int indexed chainId,
        address indexed receiver,
        uint totalValue,
        uint transferValue,
        bytes dataWithSelector,
        uint callbackGasValue
    );

    /// ===== BRIDGE CALL =====

    /// @dev Bridge the value to another chain with optional call to receiver contract and optional callback to the source chain
    /// @param chainId The chain id to bridge to. Negative values for non-EVM chains
    /// @param receiver The receiver address on the other chain
    /// @param transferValue The exact value to transfer to the receiver (in destination chain native token). Use type(uint).max to transfer max
    /// @param dataWithSelector The abiEncodeWithSelector data to send to the receiver contract (optional), when empty then simple transfer
    /// @param callbackGasValue The gas value to call callback on source chain with return data (optional: 0 - callback not needed). Sender must implement IBridgeCallback. callbackGasValue is deducted from the msg.value and not transferred to the receiver.
    /// @return jobId The id of the new bridge transfer job
    function bridge(int chainId, address receiver, uint transferValue, bytes calldata dataWithSelector, uint callbackGasValue)
    external payable returns (uint jobId)  {
        if (msg.value < minValue) revert ValueTooSmall();
        coprocessor.transfer(msg.value);
        jobId = id++;
        emit Bridge(jobId, coprocessor.balance, chainId, receiver, msg.value, transferValue, dataWithSelector, callbackGasValue);
    }

    receive() external payable {}

    function flashLoan(uint amount) external {
        uint balance = address(this).balance;
        msg.sender.transfer(amount);
        uint fee = amount >> 10; // Same as amount / 1024 or amount * 0.09765625%
        IFlashLoanCallback(msg.sender).flashLoanCallback(fee);
        if (address(this).balance < (balance + fee)) revert WrongBalance();
    }


    // ===== JOB =====

    // Function to create a new job
    function newJob() public payable {
        if (msg.value < minValue) revert ValueTooSmall();
        coprocessor.transfer(msg.value);
        emit NewJob(id);
        id++;
    }

    function getResult(uint _job_id) public view returns (string memory) {
        return jobs[_job_id];
    }

    function callback(string calldata _result, uint256 _job_id) public {
        if (msg.sender != coprocessor) revert OnlyCoprocessor();
        jobs[_job_id] = _result;
    }
}
