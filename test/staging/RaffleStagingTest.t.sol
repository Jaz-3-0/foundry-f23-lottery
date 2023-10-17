// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import { DeployRaffle } from "../../script/DeployRaffle.s.sol";
import { Raffle } from "../../src/Raffle.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
import { Test, Console } from "forge-std/Script.sol";
import { Vm } from "forge-std/Vm.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { VRFCoordinatorV2Mock } from "../../script/Interactions.s.sol";
import {CreateSubscription } from "../../script/Interactions.s.sol";

contract RaffleTest is StdCheats, Test {
    /*Errors */
    event RequestedRaffleWinner(uint256 indexed requestId);
    event RaffleEnter(address indexed player);
    event  WinnerPicked(address indexed player);

    Raffle public raffle;
    HelperConfig public helperConfig;

    uint64 subscriptionId;
    bytes32 gasLane;
    uint256 automationUpdateInterval;
    uint256 raffleEntranceFee;
    uint32 callbackGasLimit;
    address vrfCoordinatorV2;

    address public constant PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        vm.deal(PLAYER, STARTING_USER_BALANCE);

        (
            ,
            gasLane,
            automationUpdateInterval,
            raffleEntranceFee,
            callbackGasLimit,
            vrfCoordinatorV2, 
            //deployerKey
            ,
        ) = helperConfig.activeNetworkConfig();
    }

    ///////////////////////////////////
    ////////fulFillRandomWords ///////
    //////////////////////////////////

    modifier raffleEntered() {
        vm.prank(PLAYER);
        raffle.enterRaffle{ value: raffleEntranceFee}();
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1);
        _;
    }

    modifier onlyOnDeployedContracts() {
        if (block.chainid == 31337) {
            return;
        } 
        try vm.activeFork() returns(uint256) {
            return;
        } catch {
            _;
        }
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerfomUpkeep()
    public raffleEntered onlyOnDeployedContracts {
        //Arrange
        //Act / assert

        vm.expectRevert("nonexistent request");
        //vm.mockCall could be used here
        VRFCoordinatorV2Mock(vrfCoordinatorV2).fulFillRandomWords(0, address(raffle));
        vm.expectRevert("nonexistent request");

        VRFCoordinatorV2Mock(vrfCoordinatorV2).fulFillRandomWords(1, address(raffle));

    }

    function testFulfillRandomWordsPicksWinnerResetAndSendsMoney() public raffleEntered onlyOnDeployedContracts {
        address expectedWinner = address(1);

        // Arrange
        uint256 addditionalEntrances = 3;
        uint256 startingIndex = 1; //We have starting index be 1 so we can start with address(1) and not address(0)

        for(uint256 i = startingIndex; i < startingIndex + addditionalEntrances; i++) {
            address player = address(uint160(i));
            hoax(player, 1 ether); //deal 1 ether to the player
            raffle.enterRaffle{ value: raffleEntranceFee}();
        }

        uint256 startingTimestamp = raffle.getLastTimeStamp();
        uint256 startingBalance = expectedWinner.balance;

        //Act
        vm.recordLogs();
        raffle.performUpkeep(""); //emits requestId
        vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = enteries[1]; //get the requestId from the logs

        VRFCoordinatorV2Mock(vrfCoordinatorV2).fulFillRandomWords(uint256(requestId, address(raffle)));

        //Assert
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance =  recentWinner.balance;
        uint256 endingTimestamp = raffle.getLastTimeStamp();
        uint256 prize = raffleEntranceFee * (addditionalEntrances + 1);

        assert(recentWinner == expectedWinner);
        assert(uint256(raffleState) == 0);
        assert(winnerBalance == startingBalance + prize);
        assert(endingTimestampTimestamp > startingTimestamp);
    }
    
}