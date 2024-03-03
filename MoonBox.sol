// SPDX-License-Identifier: MIT
// https://t.me/coqinabox

pragma solidity ^0.8.4;

import "./DN404.sol";
import "./DN404Mirror.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {LibString} from "solady/src/utils/LibString.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import './IPancakeSwapRouter02.sol';
import "./IPancakeFactory.sol";
import "./IStaking.sol";


contract MoonBox is DN404, Ownable {
    string private _name;
    string private _symbol;
    string private _baseURI;

    address routerAddress = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address DEAD_WALLET = 0x000000000000000000000000000000000000dEaD;

    address public teamWallet;
	uint256 public swapThreshold = 10**18;
    
	
	uint256[] public liquidityFee;
	uint256[] public burnFee;
	uint256[] public teamFee;
	uint256[] public stakingRewardFee;
	
	
	uint256 private liquidityFeeTotal;
    uint256 private teamFeeTotal;
	
	bool private swapping;
	IStaking public Staking;
	
	mapping(address => bool) public isWalletTaxFree;
	mapping(address => bool) public isLiquidityPair;
	
	event WalletExemptFromTxnLimit(address wallet, bool value);
	event WalletExemptFromHoldingLimit(address wallet, bool value);
	event SwapingThresholdUpdated(uint256 amount);
	event TokenPerWalletLimitUpdated(uint256 amount);
	event TokenPerTxnLimitUpdated(uint256 amount);
	event NewLiquidityPairUpdated(address pair, bool value);
	event WalletExemptFromFee(address wallet, bool value);
	event TeamWalletUpdated(address wallet);
	event LiquidityFeeUpdated(uint256 buy, uint256 sell);
	event StakingRewardFeeUpdated(uint256 buy, uint256 sell);
	event TeamFeeUpdated(uint256 buy, uint256 sell);

    string public baseTokenURI;
    string public dataURI = 'https://raw.githubusercontent.com/MoonBoxBNB/assets/main/';

    bool unboxing = true;

    constructor() {
        _initializeOwner(msg.sender);
        _name = "Moon Box";
        _symbol = "MUNBOX";

        address mirror = address(new DN404Mirror(msg.sender));
        _initializeDN404(100000 * 10**18, msg.sender, mirror);
        address pair = IJoeFactory(IPancakeSwapRouter02(routerAddress).factory()).createPair(address(this), IPancakeSwapRouter02(routerAddress).WETH());
        _setSkipNFT(pair, true);
        isLiquidityPair[address(pair)] = true;
        isWalletTaxFree[address(this)] = true;
        isWalletTaxFree[address(msg.sender)] = true;
        isWalletTaxFree[address(mirror)] = true;
        teamWallet = msg.sender;
        //Fees 8%
        liquidityFee.push(100);
        liquidityFee.push(100);

        burnFee.push(100);
        burnFee.push(100);

        teamFee.push(100);
        teamFee.push(100);

        stakingRewardFee.push(500);
        stakingRewardFee.push(500);
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        if (bytes(baseTokenURI).length > 0) {
            return string.concat(baseTokenURI, LibString.toString(id));
        } else {
            uint8 seed = uint8(bytes1(keccak256(abi.encodePacked(id))));
            string memory image;
            string memory color;

            if (seed <= 90) {
                image = "1.gif";
                color = "red";
            } else if (seed <= 150) {
                image = "2.gif";
                color = "Green";
            } else if (seed <= 202) {
                image = "3.gif";
                color = "Blue";
            } else if (seed <= 232) {
                image = "4.gif";
                color = "Yellow";
            } else if (seed <= 242) {
                image = "5.gif";
                color = "Purple";
            } else if (seed <= 249) {
                image = "6.gif";
                color = "Silver";
            } else if (seed <= 254) {
                image = "7.gif";
                color = "Gold";
            } else if (seed <= 255) {
                image = "8.gif";
                color = "Diamond";
            }

            string memory jsonPreImage = string.concat(
                string.concat(
                    string.concat('{"name": "Moon Box #', LibString.toString(id)),
                    '","description":"A collection of 10,000 Moon Bags enabled by DN404, an experimental token standard.","external_url":"https://www.moonbag.xyz","image":"'
                ),
                string.concat(dataURI, image)
            );
            string memory jsonPostImage = string.concat(
                '","attributes":[{"trait_type":"Color","value":"',
                color
            );
            string memory jsonPostTraits = '"}]}';

            return
                string.concat(
                    "data:application/json;utf8,",
                    string.concat(
                        string.concat(jsonPreImage, jsonPostImage),
                        jsonPostTraits
                    )
                );
        }
    }

    function setBaseURI(string calldata baseURI_) public onlyOwner {
        _baseURI = baseURI_;
    }

    function exemptWalletFromFee(address wallet, bool status) external onlyOwner{
        require(wallet != address(0), "Zero address");
		require(isWalletTaxFree[wallet] != status, "Wallet is already the value of 'status'");
		
		isWalletTaxFree[wallet] = status;
        emit WalletExemptFromFee(wallet, status);
    }

    function updateSwapingThreshold(uint256 amount) external onlyOwner {
        require(amount <= totalSupply(), "Amount cannot be over the total supply.");
		require(amount >= (1 * 10**18), "Amount cannot be less than `1` token.");
		
		swapThreshold  = amount;
		emit SwapingThresholdUpdated(amount);
    }

    function updateLiquidityPair(address _pair, bool value) external onlyOwner {
        require(_pair != address(0), "Zero address");
		require(isLiquidityPair[_pair] != value, "Pair is already the value of 'value'");
		
        isLiquidityPair[_pair] = value;
        emit NewLiquidityPairUpdated(_pair, value);
    }

    function updateTeamWallet(address newWallet) external onlyOwner {
        require(address(newWallet) != address(0), "Zero address");
		
		teamWallet = address(newWallet);
        emit TeamWalletUpdated(address(newWallet));
    }

    function updateLiquidityFee(uint256 buy, uint256 sell) external onlyOwner {
	    require(teamFee[0] + stakingRewardFee[0] + burnFee[0] + buy  <= 2000 , "Max fee limit reached for 'BUY'");
		require(teamFee[1] + stakingRewardFee[1] + burnFee[1] + sell <= 2000 , "Max fee limit reached for 'SELL'");
		
		liquidityFee[0] = buy;
		liquidityFee[1] = sell;
		emit LiquidityFeeUpdated(buy, sell);
	}

    function updateStakingRewardFee(uint256 buy, uint256 sell) external onlyOwner {
	    require(teamFee[0] + liquidityFee[0] + burnFee[0] + buy  <= 2000 , "Max fee limit reached for 'BUY'");
		require(teamFee[1] + liquidityFee[1] + burnFee[1] + sell <= 2000 , "Max fee limit reached for 'SELL'");
		
		stakingRewardFee[0] = buy;
		stakingRewardFee[1] = sell;
		emit StakingRewardFeeUpdated(buy, sell);
	}

    function updateTeamFee(uint256 buy, uint256 sell) external onlyOwner {
	    require(stakingRewardFee[0] + liquidityFee[0] + burnFee[0] + buy  <= 2000 , "Max fee limit reached for 'BUY'");
		require(stakingRewardFee[1] + liquidityFee[1] + burnFee[1] + sell <= 2000 , "Max fee limit reached for 'SELL'");
		
		teamFee[0] = buy;
		teamFee[1] = sell;
		emit TeamFeeUpdated(buy, sell);
	}
    function updateBurnFee(uint256 buy, uint256 sell) external onlyOwner {
	    require(stakingRewardFee[0] + liquidityFee[0] + teamFee[0] + buy  <= 2000 , "Max fee limit reached for 'BUY'");
		require(stakingRewardFee[1] + liquidityFee[1] + teamFee[1] + sell <= 2000 , "Max fee limit reached for 'SELL'");
		
		burnFee[0] = buy;
		burnFee[1] = sell;
		emit TeamFeeUpdated(buy, sell);
	}

    function updateStakingContract(IStaking contractAddress) external onlyOwner {
        require(address(contractAddress) != address(0), "Zero address");
        require(address(Staking) == address(0), "Staking contract already set");
        
        Staking = IStaking(contractAddress);
        isWalletTaxFree[address(Staking)] = true;
    }

    function collectFee(uint256 amount, bool sell) private returns (uint256, uint256, uint256) {
	    uint256 newStakingRewardFee = amount * (sell ? stakingRewardFee[1] : stakingRewardFee[0]) / 10000;
        uint256 newLiquidityFee = amount * (sell ? liquidityFee[1] : liquidityFee[0]) / 10000;
		uint256 newTeamFee = amount * (sell ? teamFee[1] : teamFee[0]) / 10000;
		uint256 newBurnFee = amount * (sell ? burnFee[1] : burnFee[0]) / 10000;
		
	    liquidityFeeTotal += newLiquidityFee;
		teamFeeTotal += newTeamFee;
        return ((newLiquidityFee + newTeamFee), newStakingRewardFee, newBurnFee);
    }

    function swapTokensForBNB(uint256 amount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = IPancakeSwapRouter02(routerAddress).WETH();
		
        _approve(address(this), routerAddress, amount);
        IPancakeSwapRouter02(routerAddress).swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 BNBAmount) private {
        _approve(address(this), routerAddress, tokenAmount);
        IPancakeSwapRouter02(routerAddress).addLiquidityETH{value: BNBAmount}(
            address(this),
            tokenAmount,
            0,
            0,
            DEAD_WALLET,
            block.timestamp
        );
    }

    function _transfer(address from, address to, uint256 amount) internal override {      
        require(from != address(0), "transfer to the zero address");
        require(to != address(0), "transfer from the zero address");
		
		uint256 contractTokenBalance = balanceOf(address(this));
		bool canSwap = contractTokenBalance >= swapThreshold;
		
		if(!swapping && canSwap && isLiquidityPair[to]) 
		{
		    uint256 tokenToLiqudity = liquidityFeeTotal / 2;
			uint256 tokenToTeam = teamFeeTotal;
			uint256 tokenToSwap = tokenToLiqudity + tokenToTeam;
			
			if(tokenToSwap >= swapThreshold)
			{
			    swapping = true;
				swapTokensForBNB(tokenToSwap);
				uint256 BNBBalance = address(this).balance;
				
				uint256 liqudityPart = (BNBBalance * tokenToLiqudity) / tokenToSwap;
				uint256 teamPart = BNBBalance - liqudityPart;
				
				if(liqudityPart > 0)
				{
					addLiquidity(tokenToLiqudity / 2, liqudityPart);
					liquidityFeeTotal = 0;
				}
				if(teamPart > 0) 
				{
                    (bool success, ) = teamWallet.call{value: teamPart}("");
                    require(success, "Failed to send BNB on infrastructure wallet");
				    teamFeeTotal = 0;
				}
				swapping = false;
			}
		}
		
		if(isWalletTaxFree[to] || isWalletTaxFree[from])
		{
		    super._transfer(from, to, amount);
		}
		else
		{
			(uint256 contractShare, uint256 stakingShare, uint256 burnShare) = collectFee(amount, isLiquidityPair[to]);
		    if(contractShare > 0) 
		    {   
                balanceOf(address(this)) >= contractShare;
			    super._transfer(from, address(this), contractShare);
		    }
			if(stakingShare > 0)
		    {
                super._transfer(from, address(Staking), stakingShare);
                Staking.updatePool(stakingShare);
		    }
            if(burnShare > 0){
                super._transfer(from, DEAD_WALLET, burnShare);
            }
		    super._transfer(from, to, amount - (contractShare + stakingShare + burnShare));

            if (unboxing && from != owner() && isLiquidityPair[from]) {
            // Require that a receiving wallet will not hold more than 1% of supply after a transfer whilst lubrication is in effect
            require(
                balanceOf(to) <= totalSupply() / 100,
                "Just getting warmed up, limit of 1% of Coq In a Box can be held until Lubrication is complete!"
            );
        }
		}
    }

    function withdraw() public onlyOwner {
        payable(address(owner())).transfer(address(this).balance);
    }

    function setDataURI(string memory _dataURI) public onlyOwner {
        dataURI = _dataURI;
    }

    function setTokenURI(string memory _tokenURI) public onlyOwner {
        baseTokenURI = _tokenURI;
    }


    function setUnboxing(bool _state) public onlyOwner {
        unboxing = _state;
    }

    function rescueBNB() public onlyOwner {
        payable(teamWallet).transfer(address(this).balance);
    }

    function recueErc20(address tokenAddress) public onlyOwner {
        IERC20(tokenAddress).transfer(owner(), IERC20(tokenAddress).balanceOf(address(this)));
    }


    receive() external override payable {}
}