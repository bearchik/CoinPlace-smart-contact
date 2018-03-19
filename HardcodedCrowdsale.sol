pragma solidity ^0.4.18;

// Created by LLC "Uinkey" bearchik@gmail.com

library SafeMath {
  function mul(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  function div(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a / b;
    return c;
  }

  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    assert(b <= a);
    return a - b;
  }

  function add(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a + b;
    assert(c >= a);
    return c;
  }
}

interface ManagedToken{
    function setLock(bool _newLockState) public returns (bool success);
    function mint(address _for, uint256 _amount) public returns (bool success);
    function demint(address _for, uint256 _amount) public returns (bool success);
    function decimals() view public returns (uint8 decDigits);
    function totalSupply() view public returns (uint256 supply);
    function balanceOf(address _owner) view public returns (uint256 balance);
}
  
contract HardcodedCrowdsale {
    using SafeMath for uint256;

    //global definisions

    enum ICOStateEnum {NotStarted, Started, Refunded, Successful}

    address public owner = msg.sender;
    ManagedToken public managedTokenLedger;

    string public name = "Coinplace";
    string public symbol = "CPL";

    bool public halted = false;
     
    uint256 public minTokensToBuy = 100;
    
    uint256 public preICOcontributors = 0;

    uint256 public preICOstart = 1521518400; //20 Mar 2018 13:00:00 GMT+9
    uint256 public preICOend = 1526788800; // 20 May 2018 13:00:00 GMT+9
    uint256 public preHardcap = 20000 ether; 
    uint256 public preICOcollected = 0;
    uint256 public preSoftcap = 200 ether;
    uint256 public preICOtokensSold = 0;
    ICOStateEnum public preICOstate = ICOStateEnum.NotStarted;
    
    uint8 public decimals = 9;
    uint256 public DECIMAL_MULTIPLIER = 10**uint256(decimals);

    uint8 public saleIndex = 0;
 
    uint256 public preICOprice = uint256(1 ether).div(1000);
    uint256[3] public preICObonusMultipiersInPercent = [150, 145, 140];
    uint256[3] public preICOcoinsLeft = [1000000*DECIMAL_MULTIPLIER, 1000000*DECIMAL_MULTIPLIER, 1000000*DECIMAL_MULTIPLIER];
    uint256 public totalPreICOavailibleWithBonus = 4350000*DECIMAL_MULTIPLIER; 
    uint256 public maxIssuedWithAmountBasedBonus = 4650000*DECIMAL_MULTIPLIER; 
    uint256[4] public preICOamountBonusLimits = [5 ether, 20 ether, 50 ether, 300 ether];
    uint256[4] public preICOamountBonusMultipierInPercent = [103, 105, 107, 110]; // count bonus
    uint256[5] public preICOweekBonus = [130, 125, 120, 115, 110]; // time bonus

    mapping(address => uint256) public weiForRefundPreICO;

    mapping(address => uint256) public weiToRecoverPreICO;

    mapping(address => uint256) public balancesForPreICO;

    event Purchased(address indexed _from, uint256 _value);

    function advanceState() public returns (bool success) {
        transitionState();
        return true;
    }

    function transitionState() internal {
        if (now >= preICOstart) {
            if (preICOstate == ICOStateEnum.NotStarted) {
                preICOstate = ICOStateEnum.Started;
            }
            if (preHardcap > 0 && preICOcollected >= preHardcap) {
                preICOstate = ICOStateEnum.Successful;
            }
            if ( (saleIndex == preICOcoinsLeft.length) && (preICOcoinsLeft[saleIndex-1] == 0) ) {
                preICOstate = ICOStateEnum.Successful;
            }
        } if (now >= preICOend) {
            if (preICOstate == ICOStateEnum.Started) {
                if (preICOcollected >= preHardcap) {
                    preICOstate = ICOStateEnum.Successful;
                } else {
                    preICOstate = ICOStateEnum.Refunded;
                }
            }
        } 
    }

    modifier stateTransition() {
        transitionState();
        _;
        transitionState();
    }

    modifier notHalted() {
        require(!halted);
        _;
    }

    // Ownership

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0));      
        OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function balanceOf(address _owner) view public returns (uint256 balance) {
        return managedTokenLedger.balanceOf(_owner);
    }

    function totalSupply() view public returns (uint256 balance) {
        return managedTokenLedger.totalSupply();
    }


    function HardcodedCrowdsale (address _newLedgerAddress) public {
        require(_newLedgerAddress != address(0));
        managedTokenLedger = ManagedToken(_newLedgerAddress);
        assert(managedTokenLedger.decimals() == decimals);
    }

    function setNameAndTicker(string _name, string _symbol) onlyOwner public returns (bool success) {
        require(bytes(_name).length > 1);
        require(bytes(_symbol).length > 1);
        name = _name;
        symbol = _symbol;
        return true;
    }

    function setLedger (address _newLedgerAddress) onlyOwner public returns (bool success) {
        require(_newLedgerAddress != address(0));
        managedTokenLedger = ManagedToken(_newLedgerAddress);
        assert(managedTokenLedger.decimals() == decimals);
        return true;
    }

    function () payable stateTransition notHalted external {
        require(msg.value > 0);
        require(preICOstate == ICOStateEnum.Started);
        assert(preICOBuy());
    }

    
    function finalize() stateTransition public returns (bool success) {
        require(preICOstate == ICOStateEnum.Successful);
        owner.transfer(preICOcollected);
        return true;
    }

    function setHalt(bool _halt) onlyOwner public returns (bool success) {
        halted = _halt;
        return true;
    }

    function calculateAmountBoughtPreICO(uint256 _weisSentScaled, uint256 _amountBonusMultiplier) 
        internal returns (uint256 _tokensToBuyScaled, uint256 _weisLeftScaled) {
        uint256 value = _weisSentScaled;
        uint256 totalPurchased = 0;
        for (uint8 i = saleIndex; i < preICOcoinsLeft.length; i++) {
            if (preICOcoinsLeft[i] == 0) {
                continue;
            }
            uint256 forThisRate = value.div(preICOprice);
            if (forThisRate == 0) {
                break;
            }
            if (forThisRate >= preICOcoinsLeft[i]) {
                forThisRate = preICOcoinsLeft[i];
                preICOcoinsLeft[i] = 0;
                saleIndex = i+1;
            } else {
                preICOcoinsLeft[i] = preICOcoinsLeft[i].sub(forThisRate);
            }
            uint256 consumed = forThisRate.mul(preICOprice);
	    uint256 weekbonus = getWeekBonus(forThisRate).sub(forThisRate);
            value = value.sub(consumed);
            forThisRate = forThisRate.mul(_amountBonusMultiplier.add(preICObonusMultipiersInPercent[i]).sub(100)).div(100);
            totalPurchased = totalPurchased.add(forThisRate).add(weekbonus);
        }
        return (totalPurchased, value);
    }

    function getBonusMultipierInPercents(uint256 _sentAmount) public view returns (uint256 _multi) {
        uint256 bonusMultiplier = 100;
        for (uint8 i = 0; i < preICOamountBonusLimits.length; i++) {
            if (_sentAmount < preICOamountBonusLimits[i]) {
                break;
            } else {
                bonusMultiplier = preICOamountBonusMultipierInPercent[i];
            }
        }
        return bonusMultiplier;
    }
    
    function getWeekBonus(uint256 amountTokens) internal view returns(uint256 count) {
        uint256 countCoints = 0;
        uint256 bonusMultiplier = 100;
        if(block.timestamp <= (preICOstart + 1 weeks)) {
            countCoints = amountTokens.mul(preICOweekBonus[0] );
        } else if (block.timestamp <= (preICOstart + 2 weeks) && block.timestamp <= (preICOstart + 3 weeks)) {
            countCoints = amountTokens.mul(preICOweekBonus[1] );
        } else if (block.timestamp <= (preICOstart + 4 weeks) && block.timestamp <= (preICOstart + 5 weeks)) {
            countCoints = amountTokens.mul(preICOweekBonus[2] );
        } else if (block.timestamp <= (preICOstart + 6 weeks) && block.timestamp <= (preICOstart + 7 weeks)) {
            countCoints = amountTokens.mul(preICOweekBonus[3] );
        } else {
            countCoints = amountTokens.mul(preICOweekBonus[4] );
        }
        return countCoints.div(bonusMultiplier);
    }

    function preICOBuy() internal notHalted returns (bool success) {
        uint256 weisSentScaled = msg.value.mul(DECIMAL_MULTIPLIER);
        address _for = msg.sender;
        uint256 amountBonus = getBonusMultipierInPercents(msg.value);
        var (tokensBought, fundsLeftScaled) = calculateAmountBoughtPreICO(weisSentScaled, amountBonus);
        if (tokensBought < minTokensToBuy.mul(DECIMAL_MULTIPLIER)) {
            revert();
        }
        uint256 fundsLeft = fundsLeftScaled.div(DECIMAL_MULTIPLIER);
        uint256 totalSpent = msg.value.sub(fundsLeft);
        if (balanceOf(_for) == 0) {
            preICOcontributors = preICOcontributors + 1;
        }
        managedTokenLedger.mint(_for, tokensBought);
        balancesForPreICO[_for] = balancesForPreICO[_for].add(tokensBought);
        weiForRefundPreICO[_for] = weiForRefundPreICO[_for].add(totalSpent);
        weiToRecoverPreICO[_for] = weiToRecoverPreICO[_for].add(fundsLeft);
        Purchased(_for, tokensBought);
        preICOcollected = preICOcollected.add(totalSpent);
        preICOtokensSold = preICOtokensSold.add(tokensBought);
        return true;
    }

    function recoverLeftoversPreICO() stateTransition notHalted public returns (bool success) {
        require(preICOstate != ICOStateEnum.NotStarted);
        uint256 value = weiToRecoverPreICO[msg.sender];
        delete weiToRecoverPreICO[msg.sender];
        msg.sender.transfer(value);
        return true;
    }

    function refundPreICO() stateTransition notHalted public returns (bool success) {
        require(preICOstate == ICOStateEnum.Refunded);
        uint256 value = weiForRefundPreICO[msg.sender];
        delete weiForRefundPreICO[msg.sender];
        uint256 tokenValue = balancesForPreICO[msg.sender];
        delete balancesForPreICO[msg.sender];
        managedTokenLedger.demint(msg.sender, tokenValue);
        msg.sender.transfer(value);
        return true;
    }
    
    function withdrawFunds() onlyOwner public returns (bool success) {
        require(preSoftcap <= preICOcollected);
        owner.transfer(preICOcollected);
        preICOcollected = 0;
        return true;
    }
    
    function manualSendTokens(address rAddress, uint256 amount) onlyOwner public returns (bool success) {
        managedTokenLedger.mint(rAddress, amount);
        balancesForPreICO[rAddress] = balancesForPreICO[rAddress].add(amount);
        Purchased(rAddress, amount);
        preICOtokensSold = preICOtokensSold.add(amount);
        return true;
    } 

    function cleanup() onlyOwner public {
        selfdestruct(owner);
    }

}