// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

struct Receipt {
    address payable initiator;
    bool success;
    bytes returnData;
    uint change;
}

contract Coprocessor {
    address payable public immutable coprocessor;
    uint public immutable minimalValue = 0.001 ether;

    uint public id = 0;

    mapping(uint => Receipt) public receipts;

    mapping(uint => string) public jobs;

    error NotEnoughValue();
    error OnlyCoprocessor();
    error ReceiptAlreadyExists();
    error OnlyInitiator();


    constructor(address _coprocessor) {
        coprocessor = payable(_coprocessor);
    }

    event NewJob(uint indexed job_id);

    event Bridge(uint indexed id, uint balance, uint indexed chainId,
        address indexed receiver, uint totalValue, uint transferValue, bytes data);
    event NewReceipt(uint indexed id, address indexed caller, bool success, bytes returnData, uint change);
    event ClearReceipt(uint indexed id, address indexed caller);


    /// ===== BRIDGE CALL =====

    /// @dev Bridge the value to another chain
    /// @param chainId The chain id to bridge to
    /// @param receiver The receiver address on the other chain
    /// @param transferValue The value to transfer to the receiver. Use type(uint).max to transfer all
    /// @param data The data to send to the receiver contract (optional)
    /// @return newJobId The id of the new bridge transfer job
    function bridge(uint chainId, address receiver, uint transferValue, bytes calldata data)
    public payable returns (uint newJobId) {
        uint totalValue = msg.value;
        if (totalValue < minimalValue) revert NotEnoughValue();
        coprocessor.transfer(totalValue);
        newJobId = id;
        emit Bridge(newJobId, coprocessor.balance, chainId, receiver, totalValue, transferValue, data);
        id = newJobId + 1;
    }

    /// @dev Callback function to receive the result of the bridge transfer
    /// @param _id The id of the bridge transfer
    /// @param initiator The bridge job initiator address
    /// @param success The success status of the bridge transfer (target contract call)
    /// @param returnData The return data of the target contract call or error data (if not success)
    /// @param change The change value to send back to the caller
    function setReceipt(uint _id, address payable initiator, bool success, bytes calldata returnData, uint change) public {
        if (msg.sender != coprocessor) revert OnlyCoprocessor();
        if (receipts[_id].initiator != address(0)) revert ReceiptAlreadyExists();
        receipts[_id] = Receipt(initiator, success, returnData, change);
        if (change > 0) payable(msg.sender).transfer(change);
//        emit NewReceipt(_id, caller, success, returnData, change);
    }

    /// @dev Clear the receipt and send the change back to the caller
    function clearReceipt(uint _id) public {
        if (msg.sender != receipts[_id].initiator) revert OnlyInitiator();
        delete receipts[_id];
//        emit ClearReceipt(_id, msg.sender, change);
    }




    // ===== JOB =====

    // Function to create a new job
    function newJob() public payable {
        if (msg.value < minimalValue) revert NotEnoughValue();
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
