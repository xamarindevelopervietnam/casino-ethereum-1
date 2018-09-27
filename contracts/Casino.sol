pragma solidity ^0.4.24;

import 'openzeppelin-solidity/contracts/math/SafeMath.sol';
import 'openzeppelin-solidity/contracts/ownership/Ownable.sol';
import './Signable.sol';

contract Casino is Ownable, Signable {

  uint constant HOUSE_EDGE_PERCENT = 2;
  uint constant HOUSE_EDGE_MINIMUM_AMOUNT = 0.0003 ether;

  uint constant BET_AMOUNT_MIN = 0.01 ether;
  uint constant BET_AMOUNT_MAX = 1000 ether;

  uint constant BET_EXPIRATION_BLOCKS = 250;

  uint public betNonce = 0;
  uint public deposit;

  struct Bet {
    uint8 choice;
    uint8 modulo;
    uint  amount;
    uint  winAmount;
    uint  placeBlockNumber;
    address player;
  }
  mapping (uint => Bet) bets;

  event LogParticipant(address indexed player, uint choice, uint betNonce);
  event LogClosedBet(address indexed player, uint choice, uint betNonce, uint result, uint winAmount);
  event LogDistributeReward(address indexed addr, uint reward);
  event LogRecharge(address indexed addr, uint amount);
  event LogRefund(address indexed addr, uint amount);

  constructor() payable public {
    owner = msg.sender;
  }

  function placeBet(uint _choice, uint _modulo, uint _expiredBlockNumber) payable external {
    Bet storage bet = bets[betNonce];

    uint amount = msg.value;

    require(block.number < _expiredBlockNumber, 'this bet has expired');
    require(amount > BET_AMOUNT_MIN && amount < BET_AMOUNT_MAX, 'bet amount out of range');

    uint houseEdge = amount * HOUSE_EDGE_PERCENT / 100;
    if (houseEdge < HOUSE_EDGE_MINIMUM_AMOUNT) {
      houseEdge = HOUSE_EDGE_MINIMUM_AMOUNT;
    }

    uint winAmount = (amount - houseEdge) * _modulo;

    require(winAmount <= address(this).balance, 'contract balance is not enough');

    // deposit winAmount into this contract. Make sure contract is solvent
    deposit += winAmount;

    bet.choice = uint8(_choice);
    bet.player = msg.sender;
    bet.placeBlockNumber = block.number;
    bet.amount = amount;
    bet.winAmount = winAmount;
    bet.modulo = uint8(_modulo);

    emit LogParticipant(msg.sender, _choice, betNonce);

    betNonce++;
  }

  function closeBet(uint _betNonce) external {
    Bet storage bet = bets[_betNonce];

    uint amount = bet.amount;
    uint placeBlockNumber = bet.placeBlockNumber;
    uint modulo = bet.modulo;
    uint winAmount = 0;
    uint choice = bet.choice;
    address player = bet.player;

    require (amount > 0, 'this bet is not active');
    require (block.number > placeBlockNumber, 'close bet block number is too low');
    require (block.number <= placeBlockNumber + BET_EXPIRATION_BLOCKS, 'the block number is too low to query');

    // close this bet and set bet.amount to zero
    bet.amount = 0;

    uint result = uint(keccak256(abi.encodePacked(now))) % modulo;

    if (choice == result) {
      winAmount = bet.winAmount;
      player.transfer(winAmount);
      emit LogDistributeReward(player, winAmount);
    }
    // release winAmount deposit
    deposit -= bet.winAmount;

    emit LogClosedBet(player, choice, _betNonce, result, winAmount);
  }

  function refundBet(uint _betNonce) external onlyOwner {
    Bet storage bet = bets[_betNonce];

    uint amount = bet.amount;
    address player = bet.player;

    require(amount > 0, 'bet amount should greater than 0');

    // refund bet amount and set bet.amount to 0
    bet.amount = 0;
    player.transfer(amount);
    // release winAmount deposit
    deposit -= bet.winAmount;

    emit LogRefund(player, amount);
  }

  /**
   * @dev in order to let more people participant
   */
  function recharge() public payable {
    emit LogRecharge(msg.sender, msg.value);
  }

  /**
   * @dev owner can withdraw the remain ether
   */
  function withdraw(uint amount) external onlyOwner {
    require(amount <= address(this).balance - deposit, 'cannot withdraw amount greater than (balance - deposit)');

    owner.transfer(amount);
  }
}
 
