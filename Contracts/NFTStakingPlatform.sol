// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/**
 * @title NFT Staking Platform
 * @dev A platform where users can stake NFTs and earn ERC20 token rewards
 */
contract Project is ReentrancyGuard, Ownable, IERC721Receiver {
    IERC20 public immutable rewardToken;
    uint256 public rewardRate = 1e18; // 1 token per second per NFT

    struct StakeInfo {
        address owner;
        uint256 tokenId;
        uint256 timestamp;
        address nftContract;
    }

    mapping(address => mapping(uint256 => StakeInfo)) public stakedNFTs;
    mapping(address => uint256) public userStakeCount;
    mapping(address => uint256) public lastClaimTime;
    mapping(address => bool) public whitelistedContracts;

    event NFTStaked(address indexed user, address indexed nftContract, uint256 indexed tokenId, uint256 timestamp);
    event NFTUnstaked(address indexed user, address indexed nftContract, uint256 indexed tokenId, uint256 timestamp);
    event RewardsClaimed(address indexed user, uint256 amount);
    event ContractWhitelisted(address indexed nftContract, bool status);
    event RewardRateUpdated(uint256 newRate);

    constructor(address _rewardToken) Ownable(msg.sender) {
        rewardToken = IERC20(_rewardToken);
    }

    function stakeNFT(address nftContract, uint256 tokenId) external nonReentrant {
        require(whitelistedContracts[nftContract], "NFT contract not whitelisted");
        require(IERC721(nftContract).ownerOf(tokenId) == msg.sender, "Not NFT owner");
        require(stakedNFTs[nftContract][tokenId].owner == address(0), "NFT already staked");

        IERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);

        stakedNFTs[nftContract][tokenId] = StakeInfo({
            owner: msg.sender,
            tokenId: tokenId,
            timestamp: block.timestamp,
            nftContract: nftContract
        });

        userStakeCount[msg.sender]++;

        if (lastClaimTime[msg.sender] == 0) {
            lastClaimTime[msg.sender] = block.timestamp;
        }

        emit NFTStaked(msg.sender, nftContract, tokenId, block.timestamp);
    }

    function unstakeNFT(address nftContract, uint256 tokenId) external nonReentrant {
        StakeInfo memory stakeInfo = stakedNFTs[nftContract][tokenId];
        require(stakeInfo.owner == msg.sender, "Not your staked NFT");

        _claimRewards(msg.sender);

        delete stakedNFTs[nftContract][tokenId];
        userStakeCount[msg.sender]--;

        IERC721(nftContract).safeTransferFrom(address(this), msg.sender, tokenId);

        emit NFTUnstaked(msg.sender, nftContract, tokenId, block.timestamp);
    }

    function claimRewards() external nonReentrant {
        require(userStakeCount[msg.sender] > 0, "No NFTs staked");
        _claimRewards(msg.sender);
    }

    function _claimRewards(address user) internal {
        uint256 pendingRewards = calculatePendingRewards(user);

        if (pendingRewards > 0) {
            lastClaimTime[user] = block.timestamp;
            require(rewardToken.transfer(user, pendingRewards), "Reward transfer failed");
            emit RewardsClaimed(user, pendingRewards);
        }
    }

    function calculatePendingRewards(address user) public view returns (uint256) {
        if (userStakeCount[user] == 0 || lastClaimTime[user] == 0) {
            return 0;
        }

        uint256 timeElapsed = block.timestamp - lastClaimTime[user];
        return timeElapsed * rewardRate * userStakeCount[user];
    }

    function getStakeInfo(address nftContract, uint256 tokenId) external view returns (StakeInfo memory) {
        return stakedNFTs[nftContract][tokenId];
    }

    function setContractWhitelist(address nftContract, bool status) external onlyOwner {
        whitelistedContracts[nftContract] = status;
        emit ContractWhitelisted(nftContract, status);
    }

    function setRewardRate(uint256 newRate) external onlyOwner {
        rewardRate = newRate;
        emit RewardRateUpdated(newRate);
    }

    function withdrawRewardTokens(uint256 amount) external onlyOwner nonReentrant {
        require(rewardToken.transfer(owner(), amount), "Withdrawal failed");
    }

    function depositRewardTokens(uint256 amount) external onlyOwner nonReentrant {
        require(rewardToken.transferFrom(msg.sender, address(this), amount), "Deposit failed");
    }

    /**
     * @dev Required to receive ERC721 tokens using safeTransferFrom
     */
    function onERC721Received(
    address /* operator */,
    address /* from */,
    uint256 /* tokenId */,
    bytes calldata /* data */
) external pure override returns (bytes4) {
    return IERC721Receiver.onERC721Received.selector;
}
}
