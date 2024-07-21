// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// TODO inherit from ERC20
contract Coprocessor {
    address payable public immutable coprocessor;

    mapping(uint => string) public jobs; // TODO remove after

    uint private constant DEPOSIT_CHAIN_ID = 0;
    uint private constant REDEEM_CHAIN_ID = type(uint).max;

    constructor(address _coprocessor) {
        coprocessor = payable(_coprocessor);
    }

    event Bridge(uint indexed toChainId, address indexed receiver, uint indexed valueIn, uint coprocessorBalance);
    event Deliver(uint indexed fromChainId, address indexed receiver, uint indexed valueIn, uint coprocessorBalance);
    event Deposit(address indexed depositor, uint indexed valueIn, uint coprocessorBalance);
    event Redeem(address indexed receiver, uint indexed amount, uint coprocessorBalance);

    /// @dev Bridge the value to another chain
    /// @param toChainId The chain id to bridge to
    /// @param receiver The receiver address on the other chain
    function bridge(uint toChainId, address receiver)
    external payable  {
        coprocessor.transfer(msg.value);
        emit Bridge(toChainId, receiver, msg.value, coprocessor.balance);
    }

    function deliver(uint fromChainId, address payable receiver)
    external payable  {
        if (msg.sender != coprocessor) revert();
        receiver.transfer(msg.value);
        emit Deliver(fromChainId, receiver, msg.value, coprocessor.balance);
    }


    /// @dev Deposit network token to the coprocessor. Coprocessor will mint shares token to the sender
    function deposit()
    external payable  {
        coprocessor.transfer(msg.value);
        emit Deposit(msg.sender, msg.value, coprocessor.balance);
    }

    /// @dev Redeem shares for network token. Coprocessor will burn shares and send network token to the sender
    /// @param amount The amount of shares to redeem
    function redeem(uint amount)
    external  {
        emit Redeem(msg.sender, amount, coprocessor.balance);
    }


    // ===== JOB ===== // TODO remove after

    function getResult(uint _job_id) public view returns (string memory) {
        return jobs[_job_id];
    }

    function callback(string calldata _result, uint256 _job_id) public {
        if (msg.sender != coprocessor) revert();
        jobs[_job_id] = _result;
    }
}
