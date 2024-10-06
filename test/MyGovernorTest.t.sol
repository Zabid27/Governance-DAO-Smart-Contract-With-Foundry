// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {Box} from "../src/Box.sol";
import {TimeLock} from "../src/TimeLock.sol";
import {GovToken} from "../src/GovToken.sol";

contract MyGovernorTest is Test {
    MyGovernor gov;
    Box box;
    TimeLock timelock;
    GovToken token;

    address[] proposers;
    address[] executors;

    uint256[] values;
    bytes[] calldatas;
    address[] targets;

    address public USER = makeAddr("user");
    uint256 public constant INITIAL_SUPPLY = 100 ether;

    uint256 public constant MIN_DELAY = 3600; // 1 hr - after a vote passes
    uint256 public constant VOTING_DELAY = 1; // this is how many blocks till the vote is active
    uint256 public constant VOTING_PERIOD = 50400;

    function setUp() public {
        token = new GovToken();
        token.mint(USER, INITIAL_SUPPLY); // We've got the voting power

        vm.startPrank(USER);
        token.delegate(USER); // now we delegate the voting power to ourselves
        timelock = new TimeLock(MIN_DELAY, proposers,executors);
        gov = new MyGovernor(token, timelock);

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.TIMELOCK_ADMIN_ROLE();

        timelock.grantRole(proposerRole, address(gov));
        timelock.grantRole(executorRole, address(0));
        timelock.revokeRole(adminRole, USER);
        vm.stopPrank();

        box = new Box();
        box.transferOwnership(address(timelock));
    }

    function testCantUpdateBoxWithoutGovernance() public {
        vm.expectRevert();
        box.store(1);
    }

    function testGovernanceUpdateBox() public {
        // Set the value to store in the Box contract
        uint256 valueToStore = 888;

        // Create a proposal description
        string memory description = "store 1 in Box";

        // Encode the function call to store the value in the Box contract
        bytes memory encodeFunctionCall = abi.encodeWithSignature("store(uint256)", valueToStore);

        // Initialize the proposal arrays
        values.push(0); // no value is sent with the proposal
        calldatas.push(encodeFunctionCall); // the encoded function call
        targets.push(address(box)); // the target contract is the Box contract

        // 1. Propose to the DAO
        // Propose the update to the DAO
        uint256 proposalId = gov.propose(targets, values, calldatas, description);

        // Log the initial proposal state
        console.log("Proposal State: ", uint256(gov.state(proposalId)));

        // Fast-forward the blockchain clock to simulate the voting delay
        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);

        console.log("Proposal State: ", uint256(gov.state(proposalId)));

        // 2. Vote
        // Using castVote with reason // needs to be passed a proposalId and a uint8 support
        string memory reason = "cuz I am Zabid";

        uint8 voteWay = 1; // vote in favor of the proposal // voting yes
        vm.prank(USER);
        gov.castVoteWithReason(proposalId, voteWay, reason);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        // 3. Queue the Tx
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        gov.queue(targets, values, calldatas, descriptionHash );

        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + MIN_DELAY + 1);

        // 4. execute
        gov.execute(targets, values, calldatas, descriptionHash);

        assertEq(box.getNumber(), valueToStore);
    }

}