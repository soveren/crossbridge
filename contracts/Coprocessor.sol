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
    function bridge(uint chainId, address receiver) payable external returns (uint jobId);
}

contract Coprocessor is IBridge {
    address payable public immutable coprocessor;
    uint public immutable minValue = 0.001 ether;

    uint public id = 0; // Last job id (0 = no jobs yet)

    mapping(uint => string) public jobs;

    error ValueTooSmall();
    error OnlyCoprocessor();
    error WrongBalance();

    constructor(address _coprocessor) {
        coprocessor = payable(_coprocessor);
    }

    event Bridge(
        uint indexed joinedId,
        address indexed receiver,
        uint indexed value,
        uint coprocessorBalance
);

    /// ===== BRIDGE  =====

    /// @dev Bridge the value to another chain with optional call to receiver contract and optional callback to the source chain
    /// @param chainId The chain id to bridge to. Negative values for non-EVM chains
    /// @param receiver The receiver address on the other chain
    /// @return jobId The id of the new bridge transfer job
    function bridge(uint chainId, address receiver)
    external payable returns (uint jobId)  {
        if (msg.value < minValue) revert ValueTooSmall();
        coprocessor.transfer(msg.value);
        jobId = ++id; // We start from 1
        uint joinedId = (chainId << 128) | jobId;
        emit Bridge(joinedId, receiver, msg.value, coprocessor.balance);
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
