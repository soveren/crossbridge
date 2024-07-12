// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

contract Coprocessor {
    address payable public immutable coprocessor;
    uint public immutable minimalValue = 0.001 ether;

    uint public id = 0;
    mapping(uint => string) public jobs;

    error NotEnoughValue();
    error OnlyCoprocessor();


    constructor(address _coprocessor) {
        coprocessor = payable(_coprocessor);
    }

    event NewJob(uint indexed job_id);
    event Bridge(uint indexed id, uint balance, uint indexed chainId, address indexed receiver, uint value);


    // Function to create a new bridge job
    function bridge(uint chainId, address receiver)
    public payable returns (uint newJobId) {
        uint value = msg.value;
        if (value < minimalValue) revert NotEnoughValue();
        coprocessor.transfer(value);
        newJobId = id;
        emit Bridge(newJobId, coprocessor.balance, chainId, receiver, value);
        id = newJobId + 1;
    }


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
