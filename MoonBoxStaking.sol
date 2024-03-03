// SPDX-License-Identifier: MIT
// https://t.me/coqinabox

pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import './IPancakeSwapRouter02.sol';

contract MoonBoxStaking is Ownable {
	
    address public MoonBox;
	address public WETH;
	IPancakeSwapRouter02 public router;
	address public teamWallet;
	
	uint256 public rewardPerShare;
	uint256 public precisionFactor;
	
	uint256 public MoonBoxStaked;
	uint256 public totalDistributed;
	address[] public rewardToken;
	
	struct StakingInfo{
        uint256 stakedAmount; 
        uint256 pendingReward;
        uint256 claimedReward;
        uint256 totalClaimed;
    }
	mapping(address => StakingInfo) public mapStakingInfo;
	
	event Stake(address staker, uint256 amount);
	event Unstake(address staker, uint256 amount);
	event Harvest(address staker, uint256 amount);
	event PoolUpdated(uint256 amount);
	
    constructor(address _coqInaBox) {
        router = IPancakeSwapRouter02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        MoonBox = address(_coqInaBox);
        WETH = router.WETH();
		teamWallet = msg.sender;
        _initializeOwner(msg.sender);
        
        precisionFactor = 1 * 10**18;

		address[9] memory rewards = [0x62D0A8458eD7719FDAF978fe5929C6D342B0bFcE, 0xfb5B838b6cfEEdC2873aB27866079AC55363D37E, 0xa260E12d2B924cb899AE80BB58123ac3fEE1E2F0, 0x3203c9E46cA618C8C1cE5dC67e7e9D75f5da2377, 0x31e4efe290973ebE91b3a875a7994f650942D28F, 0x031b41e504677879370e9DBcF937283A8691Fa7f, 0x33d08D8C7a168333a85285a68C0042b39fC3741D, 0xA325Ad6D9c92B55A3Fc5aD7e412B1518F96441C0, 0x818835503F55283cd51A4399f595e295A9338753];

	    rewardToken = rewards;
    }
	
	receive() external payable {}
	
	function stake(uint256 amount) payable external {
		require(IERC20(MoonBox).balanceOf(msg.sender) >= amount, "Balance not available for staking");
		require(msg.value >= 10000000000000000, "Insufficient BNB for staking");
		if(mapStakingInfo[address(msg.sender)].stakedAmount > 0) 
		{
            uint256 pending = pendingReward(address(msg.sender));
            if(pending > 0)
			{
			    mapStakingInfo[address(msg.sender)].pendingReward = pending;
            }
        }
		IERC20(MoonBox).transferFrom(address(msg.sender), address(this), amount);
		MoonBoxStaked += amount;
		mapStakingInfo[address(msg.sender)].stakedAmount += amount;
		mapStakingInfo[address(msg.sender)].claimedReward = mapStakingInfo[address(msg.sender)].stakedAmount * rewardPerShare / precisionFactor;
        emit Stake(address(msg.sender), amount);

        if(address(this).balance > 0) {
            payable(owner()).transfer(address(this).balance);
        }
    }
	
	function unstake(uint256 token, uint256 amount) payable external {
	    require(rewardToken.length > token, "Reward token not found");
		require(mapStakingInfo[address(msg.sender)].stakedAmount >= amount, "amount is greater than available");
        require(msg.value >= 10000000000000000, "Insufficient AVAX for unstaking");
		
	    if(mapStakingInfo[address(msg.sender)].stakedAmount > amount) 
		{
			uint256 pending = pendingReward(address(msg.sender));
            if(pending > 0)
			{
			    mapStakingInfo[address(msg.sender)].pendingReward = pending;
			}
			IERC20(MoonBox).transfer(address(msg.sender), amount);
			MoonBoxStaked -= amount;
			
			mapStakingInfo[address(msg.sender)].stakedAmount -= amount;
		    mapStakingInfo[address(msg.sender)].claimedReward = mapStakingInfo[address(msg.sender)].stakedAmount * rewardPerShare / precisionFactor;
			emit Unstake(msg.sender, amount);
        }
        else
		{
		    uint256 pending = pendingReward(address(msg.sender));
            if(pending > 0)
			{
                    _swapTokenWAVAXPair(token, pending, address(msg.sender));
			}
			IERC20(MoonBox).transfer(address(msg.sender), amount);
			MoonBoxStaked -= amount;
			
			mapStakingInfo[address(msg.sender)].stakedAmount = 0;
		    mapStakingInfo[address(msg.sender)].claimedReward = 0;
			mapStakingInfo[address(msg.sender)].pendingReward = 0;
			mapStakingInfo[address(msg.sender)].totalClaimed += pending;
			emit Unstake(msg.sender, amount);
		}		
        if(address(this).balance > 0) {
            payable(owner()).transfer(address(this).balance);
        }
    }
	
	function harvest(uint256 token, uint256 amount) payable external {
	    require(rewardToken.length > token, "Reward token not found");
        require(msg.value >= 10000000000000000, "Insufficient BNB for harvesting");
		if(mapStakingInfo[address(msg.sender)].stakedAmount > 0) 
		{
		    uint256 pending = pendingReward(address(msg.sender));
            if(pending > amount)
			{
                
                _swapTokenWAVAXPair(token, amount, address(msg.sender));
                mapStakingInfo[address(msg.sender)].claimedReward += amount;
                mapStakingInfo[address(msg.sender)].totalClaimed += amount;
                emit Harvest(msg.sender, amount);
			}
			else
			{
                _swapTokenWAVAXPair(token, pending, address(msg.sender));
                mapStakingInfo[address(msg.sender)].claimedReward += pending;
                mapStakingInfo[address(msg.sender)].totalClaimed += pending;
                emit Harvest(msg.sender, pending);
			}
        } 
        if(address(this).balance > 0) {
            payable(owner()).transfer(address(this).balance);
        }
    }

	function compound() payable external {
        require(msg.value >= 10000000000000000, "Insufficient BNB for harvesting");
		uint256 pending = pendingReward(address(msg.sender));
		mapStakingInfo[address(msg.sender)].claimedReward += pending;
		mapStakingInfo[address(msg.sender)].totalClaimed += pending;
		mapStakingInfo[address(msg.sender)].stakedAmount += pending;
		emit Harvest(msg.sender, pending);
        if(address(this).balance > 0) {
            payable(owner()).transfer(address(this).balance);
        }
    }
	
	function pendingReward(address staker) public view returns (uint256) {
		if(mapStakingInfo[address(staker)].stakedAmount > 0) 
		{
            uint256 pending = (((mapStakingInfo[address(staker)].stakedAmount * rewardPerShare) / precisionFactor) + mapStakingInfo[address(staker)].pendingReward) - (mapStakingInfo[address(staker)].claimedReward);
		    return pending;
        } 
		else 
		{
		    return 0;
		}
    }
	
	function updatePool(uint256 amount) external {
		require(address(msg.sender) == address(MoonBox), "Incorrect request");
		if(MoonBoxStaked > 0)
		{
		    rewardPerShare = rewardPerShare + (amount * precisionFactor / MoonBoxStaked);
		}
		else
		{
		    IERC20(MoonBox).transfer(teamWallet, amount);
		}
		totalDistributed += amount;
		emit PoolUpdated(amount);
    }

    function setRewardsTokens(address[] memory tokens) external onlyOwner {
        rewardToken = tokens;
    }
	
	function _swapTokenWAVAXPair(uint256 token, uint256 amount, address receiver) private {
        address[] memory path = new address[](3);
        path[0] = address(MoonBox);
        path[1] = address(WETH);
		path[2] = address(rewardToken[token]);
		
		IERC20(MoonBox).approve(address(router), amount);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amount,
            0,
            path,
            address(receiver),
            block.timestamp
        );
    }

	function setTeamWallet(address _teamWallet) public onlyOwner {
		teamWallet = _teamWallet;
	}
}