//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC721} from"@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/INFTMarket_V5_1.sol";
import "./interfaces/INFTPermit.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IWETH9.sol";
import {KKToken} from "./KKToken.sol";

/**
 * @title This is an NFT exchange contract that can provide trading for ERC721 Tokens. Various ERC721 tokens are able to be traded here.
 * This contract was updated from `NFTMarket_V5`.
 * Now, part of profits of selling NFTs will be staked in this contract.
 *
 * ( NFTMarket 合约支持功能：上架 NFT、下架 NFT、购买 NFT、白名单用户领取 NFT、ERC-20 token 预授权、multicall、ETH(或WETH)质押/解除质押、将 NFT 卖出所获的部分利润投入质押、其他实用功能 )
 * ( V5 新增特性：质押功能，NFT 部分的卖家收益将自动投入到质押的收益池中，质押功能实现了两类质押方式且同时存在：)
 * ( 1. 单利质押，详见方法 {stakeWETH_SimpleStake} )
 * ( 2. 复利质押, 详见方法 {stakeWETH_CompoundStake} )
 * ( V5_1 新增特性：流动性挖矿功能，每个区块产生 10 个 KKToken 作为收益，按照质押的流动性占比分配此收益)
 *
 * @author Garen Woo
 */
contract NFTMarket_V5_1 is INFTMarket_V5_1, IERC721Receiver {
    using SafeERC20 for IERC20;
    address private owner;                              // the address of the owner of this NFTMarket contract
    address public immutable GTSTAddr;                  // the address of the default ERC-20 token used in trading NFT(s) in this NFTMarket
    address public immutable wrappedETHAddr;            // the address of WETH used in staking and trading NFT(s)
    address public immutable routerAddr;                // the address of Uniswap_v2_Router02 which provides swap between multiple types of tokens
    mapping(address NFTAddr => mapping(uint256 tokenId => uint256 priceInETH)) private price;       // the price of a specific NFT which is set at the moment of listing.
    mapping(address user => uint256 WETHBalance) private userBalanceOfWETH;     // the WETH balance of a specific user
    mapping(address user => uint256 GTSTBalance) private userBalanceOfGTST;     // the GTST balance of a specific user
    
    uint256 public constant MANTISSA = 1e18;            // a constant factor used to be multiplied by a tiny number which may be divided by a large number to avoid the loss of calculation accuracy 
    uint8 public constant FIGURE_FEERATIO = 10;         // the pure figure of the proportion of the profits of selling NFTs
    uint8 public constant FRACTION_FEERATIO = 2;        // the fraction of the proportion of the profits of selling NFTs

    // State variables of simple stake(simple interest)
    // `staker_simple`: A struct that contains the fields related to stakers of simple-stake(simple interest model).
    mapping(address account => stakerOfSimpleStake stakerStruct_simple) public staker_simple;
    uint256 public stakeInterestAdjusted;               // the number of the interest(simple stake) per stake multiplied by MANTISSA
    uint256 public stakePool_SimpleStake;               // the total amount of staked WETH
    
    // State variables of compound stake(compound interest)
    uint256 public stakePool_CompoundStake;             // the total amount of staked WETH using the algorithm of ERC4626
    address public immutable KKToken_Compound;          // the ERC-20 token used to represent the shares of ETH(WETH) staking(compound interest).

    // Staking to mine
    // `staker_simple`: A struct that contains the fields related to stakers of simple-stake(simple interest model).
    mapping(address account => stakerOfMining stakerStruct_mining) public staker_mining;
    address public immutable KKToken_Mining;            // the ERC-20 token used to represent the shares of ETH(WETH) staking(mining).
    uint256 public miningInterestAdjusted;              // the interest(mining) per staker multiplied by MANTISSA
    uint256 public minedAmountPerBlock;                 // the total amount of KK token mined in each block
    uint256 public BlockNumberLast;                     // the block number recorded when the total staked amount changes
    uint256 public stakePool_Mining;                    // the total amount of staked WETH

    constructor(address _tokenAddr, address _wrappedETHAddr, address _routerAddr, address _KKToken_Compound, uint256 _minedAmountPerBlock) {
        owner = msg.sender;
        GTSTAddr= _tokenAddr;
        wrappedETHAddr = _wrappedETHAddr;
        routerAddr = _routerAddr;
        KKToken_Compound = _KKToken_Compound;
        minedAmountPerBlock = _minedAmountPerBlock;
    }

    /**
     * @dev Only the owner of this NFTMarket contract can call the functions that are flagged with this modifier.
     */
    modifier onlyNFTMarketOwner() {
        if (msg.sender != owner) {
            revert notOwnerOfNFTMarket();
        }
        _;
    }

    receive() external payable {
        emit ETHReceived(msg.sender, msg.value);
    }


    // ------------------------------------------------------ ** List / Delist NFT ** ------------------------------------------------------

    /**
     * @notice List an NFT by its owner. This will allow the NFT to be bought by other users.
     *
     * @dev Once the NFT is listed, there will be multiple operations occur:
     * 1. The NFT will be transferred from `msg.sender` to `address(this)`. The actual owner of the NFT will be `address(this)` after this transfer.
     * 2. The NFT seller(also the previous owner of the NFT, i.e. `msg.sender`) will be approved to operate the NFT considering the operability of the NFT seller(e.g. the seller can delist its NFT at any time).
     * 3. The listed NFT will be flagged with `_priceInWETH` which is the price counted in the minimum unit of WETH.
     * 4. Emits the event {NFTListed}.
     *
     * @param _nftAddr the address of the contract where the NFT is located
     * @param _tokenId the tokenId of the NFT which is aimed to be listed by `msg.sender`
     * @param _priceInWETH the amount of WETH(counted in the minimum unit of WETH) representing the price of the listed NFT
     */
    function list(address _nftAddr, uint256 _tokenId, uint256 _priceInWETH) external {
        if (msg.sender != IERC721(_nftAddr).ownerOf(_tokenId)) {
            revert notOwnerOfNFT();
        }
        if (_priceInWETH == 0) revert zeroPrice();
        require(price[_nftAddr][_tokenId] == 0, "This NFT is already listed");
        _List(_nftAddr, _tokenId, _priceInWETH);
    }

    /**
     * @notice Validate a signature that contains the message of listing a specific NFT. Once the signature is validated to be signed by the NFT owner, the NFT will be listed.
     *
     * @dev There is a validation of the given signature prior to the functionality of listing an NFT(same as the function {list}).
     * This function validates the off-chain signature of the message signed by the owner of the NFT.
     * Emits the event {NFTListed}.
     *
     * @param _nftAddr the address of the contract where the NFT is located
     * @param _tokenId the tokenId of the NFT which is aimed to be listed by `msg.sender`
     * @param _priceInWETH the amount of WETH(counted in the minimum unit of WETH) representing the price of the listed NFT
     * @param _deadline the expired timestamp of the given signature
     * @param _v ECDSA recovery id
     * @param _r ECDSA signature r
     * @param _s ECDSA signature s
     */
    function listWithPermit(
        address _nftAddr,
        uint256 _tokenId,
        uint256 _priceInWETH,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external {
        if (_priceInWETH == 0) revert zeroPrice();
        require(price[_nftAddr][_tokenId] == 0, "This NFT is already listed");
        bool isPermitVerified = INFTPermit(_nftAddr).NFTPermit_PrepareForList(
            address(this), _tokenId, _priceInWETH, _deadline, _v, _r, _s
        );
        if (isPermitVerified) {
            _List(_nftAddr, _tokenId, _priceInWETH);
        }
    }

    /**
     * @notice Delist an NFT by the NFT seller. The NFT will be no longer available to be bought.
     * 
     * @dev  Once the NFT is delisted, there will be multiple operations occur:
     * 1. The NFT will be transferred from `address(this)` to `msg.sender`. The NFT seller(i.e `msg.sender`) will be the actual owner of the NFT (again).
     * 2. The price of the NFT will be reset as 0 (default value) which indicates the NFT is not for sale.
     * 3. Emits the event {NFTDelisted}.
     *
     * @param _nftAddr the address of the contract where the NFT is located
     * @param _tokenId the tokenId of the NFT which is aimed to be delisted by `msg.sender`
     */
    function delist(address _nftAddr, uint256 _tokenId) external {
        require(IERC721(_nftAddr).getApproved(_tokenId) == msg.sender, "Not seller or Not on sale");
        if (price[_nftAddr][_tokenId] == 0) revert notOnSale(_nftAddr, _tokenId);
        IERC721(_nftAddr).safeTransferFrom(address(this), msg.sender, _tokenId, "Delist successfully");
        delete price[_nftAddr][_tokenId];
        emit NFTDelisted(msg.sender, _nftAddr, _tokenId);
    }


    // ------------------------------------------------------ ** Buy NFT(s) ** ------------------------------------------------------

    /**
     * @notice This is a callback function that supports buying NFT using transferred ERC-20 tokens.
     * Users can buy NFT(s) via calling a function which invokes this function in the ERC-20 token contract.
     *
     * @dev Important! If your NFT project supports the functionality of buying NFT with an off-chain signature of messages, please make sure the NFT contract(s) have realized the functionality of the interface {INFTPermit}.
     * Without the realization of {INFTPermit}, malevolent EOAs can directly buy NFTs without validating the signature of the message which contains the data of the whitelist.
     * This function requires the direct caller(i.e. `msg.sender`) is a contract which has fully realized {IERC20}. 
     * The `_recipient` will try to buy NFT with the transferred ERC-20 token.
     * The NFT address and tokenId of the NFT separately come from `nftAddress` and 'tokenId', which are decoded from `data`.
     * The value of the transferred token should equal or exceed the value corresponding to the price(counted in WETH) of the NFT under purchase.
     * The given ERC-20 tokens will be swapped to WETH which is the token used for NFT trades. The excess part of the paid token will be refunded.
     * Emits the event {NFTBoughtWithAnyToken}.
     *
     * @param _recipient the NFT recipient(also the buyer of the NFT)
     * @param _ERC20TokenAddr the contract address of the ERC-20 token used for buying the NFT
     * @param _tokenAmount the amount of the ERC-20 token used for buying the NFT
     * @param _data the encoded data containing `nftAddress` and `tokenId`
     */
    function tokensReceived(address _recipient, address _ERC20TokenAddr, uint256 _tokenAmount, bytes calldata _data) external {
        (address nftAddress, uint256 tokenId) = abi.decode(_data, (address, uint256));
        bool checkResult = _beforeNFTPurchase(_recipient, _ERC20TokenAddr, nftAddress, tokenId);

        // To avoid users directly buying NFTs which require checking of whitelist membership, here check the interface existence of {_support_IERC721Permit}.
        bool isERC721PermitSupported = _support_IERC721Permit(nftAddress);
        if (isERC721PermitSupported) {
            revert ERC721PermitBoughtByWrongFunction("tokenReceived", "buyWithPermit");
        }
        
        // If all the checks have passed, here comes the execution of the NFT purchase.
        if (checkResult) {
            uint256 tokenAmountPaid = _handleNFTPurchase(_recipient, _ERC20TokenAddr, nftAddress, tokenId, _tokenAmount);
            emit NFTBoughtWithAnyToken(_recipient, _ERC20TokenAddr, nftAddress, tokenId, tokenAmountPaid);
        }
    }

    /**
     * @notice Buy an NFT using GTST(a specific ERC20-token used in this NFTMarket). 
     * The amount of paid GTST should not less than the price of the NFT under purchase.
     * All the given GTST will be spent on buying the NFT without refunding the excess.
     *
     * @dev Important! If your NFT project supports the functionality of buying NFT with an off-chain signature of messages, please make sure the NFT contract(s) have realized the functionality of the interface {INFTPermit}.
     * Without the realization of {INFTPermit}, malevolent EOAs can directly buy NFTs without validating the signature of the message which contains the data of the whitelist.
     * After the NFT purchase, the GTST balance of the NFT seller will increase by `_tokenAmount`.
     * Emits the event {NFTBoughtWithGTST}.
     *
     * @param _nftAddr the address of the contract where the NFT the buyer wants to buy is located
     * @param _tokenId the tokenId of the NFT which is aimed to be bought.
     * @param _tokenAmount the amount of paid "GTST"
     */
    function buyWithGTST(address _nftAddr, uint256 _tokenId, uint256 _tokenAmount) external {
        bool checkResult = _beforeNFTPurchase(msg.sender, GTSTAddr, _nftAddr, _tokenId);

        // To avoid users directly buying NFTs which require checking of whitelist membership, here check the interface existence of {_support_IERC721Permit}.
        bool isERC721PermitSupported = _support_IERC721Permit(_nftAddr);
        if (isERC721PermitSupported) {
            revert ERC721PermitBoughtByWrongFunction("buy", "buyWithPermit");
        }
        
        // If all the checks have passed, here comes the execution of the NFT purchase.
        if (checkResult) {
            _handleNFTPurchaseUsingGTST(msg.sender, _nftAddr, _tokenId, _tokenAmount);
            emit NFTBoughtWithGTST(msg.sender, _nftAddr, _tokenId, _tokenAmount);
        }
    }

    /**
     * @notice Buy an NFT using any ERC-20 token.
     *
     * @dev Important! If your NFT project supports the functionality of buying NFT with an off-chain signature of messages, please make sure the NFT contract(s) have realized the functionality of the interface {INFTPermit}.
     * Without the realization of {INFTPermit}, malevolent EOAs can directly buy NFTs without validating the signature of the message which contains the data of the whitelist.
     * `msg.sender` buys the NFT with any ERC-20 token. The given ERC-20 tokens will be swapped to WETH which is the token used for NFT trades. Slippage will be considered in the swap of tokens.
     * Considering the existence of slippage, the value of the transferred token should exceed the value corresponding to the price(counted in WETH) of the NFT under purchase.
     * The actual spent amount of the given ERC-20 token is calculated in the procession of the swap of tokens based on the NFT price.
     * Emits the event {NFTBoughtWithAnyToken}.
     *
     * @param _ERC20TokenAddr the contract address of the ERC-20 token used for buying the NFT
     * @param _nftAddr the address of the contract where the NFT the buyer wants to buy is located
     * @param _tokenId the tokenId of the NFT which is aimed to be bought.
     * @param _slippageFigure the significant figure of the slippage considered in the swap of tokens.
     * @param _slippageFraction the fraction of the slippage considered in the swap of tokens.
     */
    function buyNFTWithAnyToken(address _ERC20TokenAddr, address _nftAddr, uint256 _tokenId, uint256 _slippageFigure, uint256 _slippageFraction) external {
        bool checkResult = _beforeNFTPurchase(msg.sender, _ERC20TokenAddr, _nftAddr, _tokenId);

        // To avoid users directly buying NFTs which require checking of whitelist membership, here check the interface existence of {_support_IERC721Permit}.
        bool isERC721PermitSupported = _support_IERC721Permit(_nftAddr);
        if (isERC721PermitSupported) {
            revert ERC721PermitBoughtByWrongFunction("buy", "buyWithPermit");
        }
        
        // If all the checks have passed, here comes the execution of the NFT purchase.
        if (checkResult) {
            uint256 tokenAmountPaid = _handleNFTPurchaseWithSlippage(msg.sender, _ERC20TokenAddr, _nftAddr, _tokenId, _slippageFigure, _slippageFraction);
            emit NFTBoughtWithAnyToken(msg.sender, _ERC20TokenAddr, _nftAddr, _tokenId, tokenAmountPaid);
        }
    }

    /**
     * @notice Validate a signature of a message related to approval of NFT before the NFT purchase. 
     * Once the signature is validated to be signed by the NFT owner, the NFT will be allowed to be bought by the caller.
     * This function is used for a member of a whitelist(built by an NFT project) buying an NFT(specified in the whitelist).
     *
     * @dev There is a validation of the given signature prior to the functionality of buying an NFT.
     * The given signature should contain the information of the whitelist corresponding to the NFT under purchase.
     * Only the member of the whitelist is allowed to buy the NFT.
     * The given ERC-20 tokens will be swapped to WETH which is the token used for NFT trades. The excess part of the paid token will be refunded.
     * Emits the event {NFTBoughtWithPermit}.
     *
     * @param _ERC20TokenAddr the contract address of the ERC-20 token used for buying the NFT
     * @param _nftAddr the address of the contract where the NFT is located
     * @param _tokenId the tokenId of the NFT which is aimed to be bought by `msg.sender`
     * @param _tokenAmount the amount of the given ERC-20 token used for buying the NFT
     * @param _deadline the expired timestamp of the given signature
     * @param _v ECDSA recovery id
     * @param _r ECDSA signature r
     * @param _s ECDSA signature s 
     */
    function buyWithPermit(
        address _ERC20TokenAddr,
        address _nftAddr,
        uint256 _tokenId,
        uint256 _tokenAmount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external {
        bool checkResult = _beforeNFTPurchase(msg.sender, _ERC20TokenAddr, _nftAddr, _tokenId);
        
        // Validate the signature of the typed message with given inputs.
        bool isPermitVerified = INFTPermit(_nftAddr).NFTPermit_PrepareForBuy(
            msg.sender, _tokenId, _deadline, _v, _r, _s
        );

        // If all the checks have passed, here comes the execution of the NFT purchase.
        if (checkResult && isPermitVerified) {
            uint256 tokenAmountPaid = _handleNFTPurchase(msg.sender, _ERC20TokenAddr, _nftAddr, _tokenId, _tokenAmount);
            emit NFTBoughtWithPermit(msg.sender, _ERC20TokenAddr, _nftAddr, _tokenId, tokenAmountPaid);
        }
    }


    // ------------------------------------------------------ ** Withdrawal GTST or ETH ** ------------------------------------------------------

    /**
     * @notice Withdraw a custom amount of ETH from the user's WETH balance.
     *
     * @dev `msg.sender` withdraws ETH from its WETH balance in this NFTMarket contract.
     * By calling the function {withdraw} in the WETH contract, ETH corresponding to `_value` will be transferred to `address(this)`.
     * Then, the equivalent ETH will be transferred from `address(this)` to `msg.sender` of this function.
     * Emits the event {ETHWithdrawn}.
     *
     * @param _value the withdrawn amount of WETH
     */
    function withdrawFromWETHBalance(uint256 _value) external {
        if (_value > userBalanceOfWETH[msg.sender]) {
            revert withdrawalExceedBalance(_value, userBalanceOfWETH[msg.sender]);
        }
        userBalanceOfWETH[msg.sender] -= _value;
        IWETH9(wrappedETHAddr).withdraw(_value);
        (bool _success, ) = payable(msg.sender).call{value: _value}("");
        require(_success, "withdraw ETH failed");
        emit ETHWithdrawn(msg.sender, _value);
    }

    /**
     * @notice Withdraw a custom amount of GTST from the user's GTST balance.
     *
     * @dev `msg.sender` withdraws GTST from its GTST balance in this NFTMarket contract.
     * Transfer GTST from `address(this)` to `msg.sender` of this function.
     * Emits the event {GTSTWithdrawn}.
     *
     * @param _value the withdrawn amount of GTST
     */
    function withdrawFromGTSTBalance(uint256 _value) external {
        if (_value > userBalanceOfGTST[msg.sender]) {
            revert withdrawalExceedBalance(_value, userBalanceOfGTST[msg.sender]);
        }
        userBalanceOfGTST[msg.sender] -= _value;
        bool _success = IERC20(GTSTAddr).transfer(msg.sender, _value);
        require(_success, "withdraw GTST failed");
        emit GTSTWithdrawn(msg.sender, _value);
    }

    
    // ------------------------------------------------------ ** PermitPrePay & ClaimNFT ** ------------------------------------------------------

    /**
     * @notice Validate a signature that contains the message of ERC-20 token approval.
     * Once the signature is validated to be signed by the token owner, the token contract will approve this NFTMarket contract with the allowance whose amount equals `_tokenAmount`.
     * This function requires that the given ERC-20 token contract has already inherited {ERC20Permit}(i.e. ERC2612).
     * 
     * @dev Approve `address(this)` by validating an off-chain signature. This signature only be validated as valid when its derived signer equals the owner of the given ERC-20 tokens.
     * Emits the event {prepay}.
     *
     * @param _ERC20TokenAddr the contract address of the ERC-20 token used to approve `address(this)`
     * @param _tokenOwner the address of token owner that allow `address(this)` to operate its tokens
     * @param _tokenAmount the amount of the given ERC-20 token available to be operated by `address(this)`
     * @param _deadline the expired timestamp of the given signature
     * @param _v ECDSA recovery id
     * @param _r ECDSA signature r
     * @param _s ECDSA signature s 
     */
    function permitPrePay(address _ERC20TokenAddr, address _tokenOwner, uint256 _tokenAmount, uint256 _deadline, uint8 _v, bytes32 _r, bytes32 _s) public returns (bool) {
        bool isIERC20Supported = _support_IERC20(_ERC20TokenAddr);
        bool isIERC20PermitSupported = _support_IERC20Permit(_ERC20TokenAddr);
        if (!isIERC20Supported || !isIERC20PermitSupported) {
            revert notERC20PermitToken(_ERC20TokenAddr);
        }
        IERC20Permit(_ERC20TokenAddr).permit(_tokenOwner, address(this), _tokenAmount, _deadline, _v, _r, _s);
        emit prepay(_tokenOwner, _tokenAmount);
        return true;
    }

    /**
     * @notice A member in a whitelist(built by an NFT project) claims its NFT with a specified price. 
     * If the claim succeeds, the member spends an amount of WETH corresponding to the specified price and gets the NFT.
     *
     * @dev The whitelist should built as a Merkle tree by the NFT project.
     * The data of the whitelist(i.e. `_NFTWhitelistData`) including `whitelistNFTAddr` and `MerkleRoot`, should also be given by the NFT project before this claim.
     * Also, `_merkleProof` should be offered by the NFT project based on the address of the queried member.
     * The inputs(`_recipient`, `_promisedTokenId` and `_promisedPriceInETH`) should match those(user address, tokenId, NFT price) in the whitelist, respectively. Otherwise, the claim will fail.
     * Before calling this function, the caller should have approved `address(this)` sufficient allowance in the WETH contract.
     * Emits the event {NFTClaimed}.
     *
     * @param _recipient the recipient of the claimed NFT(required the membership in the whitelist
     * @param _promisedTokenId the tokenId corresponds to the NFT which is specified to a member in the whitelist
     * @param _merkleProof the Merkle proof which is a dynamic array used for validating the membership of `msg.sender` in the whitelist.
     * @param _promisedPriceInETH the promised price(unit: wei) of the NFT corresponding to `_promisedTokenId`, which is one of the fields of each Merkle tree node
     * @param _NFTWhitelistData An encoded bytes variable containing `whitelistNFTAddr` and `MerkleRoot` which is offered by the NFT Project.
     */
    function claimNFT(address _recipient, uint256 _promisedTokenId, bytes32[] memory _merkleProof, uint256 _promisedPriceInETH, bytes memory _NFTWhitelistData)
        public
    {   
        (address whitelistNFTAddr, bytes32 MerkleRoot) = abi.decode(_NFTWhitelistData, (address, bytes32));
        // Verify the membership of whitelist using Merkle tree.
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(_recipient, _promisedTokenId, _promisedPriceInETH))));
        _verifyMerkleProof(_merkleProof, MerkleRoot, leaf);
        bool _ok = IWETH9(wrappedETHAddr).transferFrom(_recipient, address(this), _promisedPriceInETH);
        require(_ok, "WETH transfer failed");
        address NFTOwner = IERC721(whitelistNFTAddr).ownerOf(_promisedTokenId);
        IERC721(whitelistNFTAddr).transferFrom(NFTOwner, _recipient, _promisedTokenId);
        userBalanceOfWETH[NFTOwner] += _promisedPriceInETH;
        emit NFTClaimed(whitelistNFTAddr, _promisedTokenId, _recipient);
    }


    // ------------------------------------------------------ ** Multicall ** ------------------------------------------------------

    /**
     * @notice Call multiple functions in any target address within one transaction.
     * The input is a dynamic array containing multiple unique calls of functions.
     * 
     * @dev Each element in the array `_calls` represents a unique call in the type of struct `Call`. 
     * Each struct `Call` specifies the target address called and the encoded data of the ABI of the called function and its input parameters.
     * Currently, it only supports the multicall of {permitPrePay} and {claimNFT}.
     *
     * @param _calls the dynamic array containing multiple unique calls in the type of struct `Call`
     */
    function aggregate(Call[] memory _calls) public returns(bytes[] memory returnData) {
        returnData = new bytes[](_calls.length);
        for (uint256 i = 0; i < _calls.length; i++) {
            (bool success, bytes memory returnBytes) = (_calls[i].target).call(_calls[i].callData);
            if (!success) {
                revert multiCallFail(i, _calls[i].callData);
            }
            returnData[i] = returnBytes;
        }
    }


    // ------------------------------------------------------ ** Stake And Unstake(Simple Interest) ** ------------------------------------------------------

    /**
     * @notice Stake ETH with simple interest(also call the stake with simple interest 'Simple Stake').
     *
     * @dev The total staked(simple stake) amount of ETH will be recorded(in the form of WETH) by the state variable `stakePool_SimpleStake`.
     * This function can stake ETH in this NFTMarket contract to earn simple interest.
     * The simple interest comes from part of the profits of selling NFT(s) which is automatically added to `stakePool_SimpleStake`(non-zero value of `stakePool_SimpleStake` required).
     * In this type of stake, `stakeInterestAdjusted` which represents the interest(multiplied by `MANTISSA`) of each staked ETH is maintained globally when `stakePool_SimpleStake` changes(non-zero value of `stakePool_SimpleStake` required).
     * Emits the event {WETHStaked_SimpleStake}.
     */
    function stakeETH_SimpleStake() public payable {
        uint256 _stakedAmount = msg.value;
        if (_stakedAmount == 0) {
            revert stakeZero();
        }
        // Update the earned interest before updating the principal.
        // When a user stakes ETH for the first time, the principal before this stake will be zero. The earned interest of this staker is zero as well.
        staker_simple[msg.sender].earned += staker_simple[msg.sender].principal * (stakeInterestAdjusted - staker_simple[msg.sender].accrualInterestAdjusted) / MANTISSA;
        // Convert the transferred ETH to WETH.
        IWETH9(wrappedETHAddr).deposit{value: _stakedAmount}();
        // Update the fields of `staker_simple`.
        staker_simple[msg.sender].principal += _stakedAmount;
        staker_simple[msg.sender].accrualInterestAdjusted = stakeInterestAdjusted;
        // Add the new staked amount of WETH into `stakePool_SimpleStake`(i.e. the total amount of the staked WETH)
        stakePool_SimpleStake += _stakedAmount;
        emit WETHStaked_SimpleStake(msg.sender, _stakedAmount, stakeInterestAdjusted);
    }

    /**
     * @notice Stake WETH with simple interest(also call the stake with simple interest 'Simple Stake').
     *
     * @dev The total staked(simple stake) amount of WETH will be recorded by the state variable `stakePool_SimpleStake`.
     * This function can stake WETH in this NFTMarket contract to earn simple interest.
     * The simple interest comes from part of the profits of selling NFT(s) which is automatically added to `stakePool_SimpleStake`(non-zero value of `stakePool_SimpleStake` required).
     * In this type of stake, `stakeInterestAdjusted` which represents the interest(multiplied by `MANTISSA`) of each staked WETH is maintained globally when `stakePool_SimpleStake` changes(non-zero value of `stakePool_SimpleStake` required).
     * Emits the event {WETHStaked_SimpleStake}.
     *
     * @param _stakedAmount the staked amount of WETH
     */
    function stakeWETH_SimpleStake(uint256 _stakedAmount) public {
        if (_stakedAmount == 0) {
            revert stakeZero();
        }
        // Update the earned interest before updating the principal.
        // When a user stakes WETH for the first time, the principal before this stake will be zero. The earned interest of this staker is zero as well.
        staker_simple[msg.sender].earned += staker_simple[msg.sender].principal * (stakeInterestAdjusted - staker_simple[msg.sender].accrualInterestAdjusted) / MANTISSA;
        // Transfer WETH from `msg.sender` to `address(this)`
        IWETH9(wrappedETHAddr).transferFrom(msg.sender, address(this), _stakedAmount);
        // Update the fields of `staker_simple`.
        staker_simple[msg.sender].principal += _stakedAmount;
        staker_simple[msg.sender].accrualInterestAdjusted = stakeInterestAdjusted;
        // Add the new staked amount of WETH into `stakePool_SimpleStake`(i.e. the total amount of the staked WETH)
        stakePool_SimpleStake += _stakedAmount;
        emit WETHStaked_SimpleStake(msg.sender, _stakedAmount, stakeInterestAdjusted);
    }

    /**
     * @notice Unstake WETH from this NFTMarket contract(simple stake).
     *
     * @dev Unstake an amount of principal equivalent to `_unstakeAmount` and also get its corresponding interest back.
     * Emits the event {WETHUnstaked_SimpleStake}.
     * 
     * @param _unstakeAmount the unstaked amount of WETH
     */
    function unstakeWETH_SimpleStake(uint256 _unstakeAmount) public {
        if (_unstakeAmount == 0 || _unstakeAmount > staker_simple[msg.sender].principal) {
            revert invalidUnstakedAmount();
        }
        // Update the earned interest before updating the principal.
        staker_simple[msg.sender].earned += staker_simple[msg.sender].principal * (stakeInterestAdjusted - staker_simple[msg.sender].accrualInterestAdjusted) / MANTISSA;
        // Calculate the earned interest corresponding to the unstaked amount of WETH based on the proportion of `_unstakeAmount` in `staker_simple[msg.sender].principal`(before minus by `_unstakeAmount`).
        uint256 correspondingInterest = _unstakeAmount * staker_simple[msg.sender].earned / staker_simple[msg.sender].principal;
        // Calculate the total amount of withdrawn WETH(including principal and earned interest)
        userBalanceOfWETH[msg.sender] += _unstakeAmount + correspondingInterest;
        // Update the fields of the unstaker.
        // Update the Amount of the earned interest of `msg.sender` after withdrawing the corresponding interest to `_unstakeAmount`.
        staker_simple[msg.sender].earned -= correspondingInterest;
        staker_simple[msg.sender].principal -= _unstakeAmount;
        staker_simple[msg.sender].accrualInterestAdjusted = stakeInterestAdjusted;
        // Withdraw the unstaked amount of WETH from `stakePool_SimpleStake`(i.e. the total amount of the staked WETH)
        stakePool_SimpleStake -= _unstakeAmount;
        emit WETHUnstaked_SimpleStake(msg.sender, _unstakeAmount, stakeInterestAdjusted);
    }
    

    // -------------------------------------------------- ** Stake And Unstake(Compound Interest) ** --------------------------------------------------

    /**
     * @notice Stake ETH with compound interest and get minted shares(i.e. KKToken_Compound)(also call the stake with compound interest 'Compound Stake').
     *
     * @dev Implement the algorithm of ERC4626(a financial model of compound interest that reinvests the interest as principal to earn future interest) to calculate the amount of minted shares(i.e. KKToken_Compound).
     * A simple example which has realized ERC4626 is presented at "https://solidity-by-example.org/defi/vault/".
     * This function can stake ETH in this NFTMarket contract to earn compound interest.
     * The compound interest comes from part of the profits of selling NFT(s) which is staked(compound stake) in this NFTMarket contract automatically without calling this function.
     * After the stake, `msg.sender` will obtain an amount of shares. Those shares can be burnt to withdraw the staked principal and its interest back.
     * Emits the event {WETHStaked_CompoundStake}.
     */
    function stakeETH_CompoundStake() public payable {
        uint256 _stakedAmount = msg.value;
        if (_stakedAmount == 0) {
            revert stakeZero();
        }
        uint256 shares;
        uint256 totalSupply = KKToken(KKToken_Compound).totalSupply();
        if (totalSupply == 0) {
            shares = _stakedAmount;
        } else {
            shares = (_stakedAmount * totalSupply) / stakePool_CompoundStake;
        }
        IWETH9(wrappedETHAddr).deposit{value: _stakedAmount}();
        KKToken(KKToken_Compound).mint(msg.sender, shares);
        stakePool_CompoundStake += _stakedAmount;
        emit WETHStaked_CompoundStake(msg.sender, _stakedAmount, shares);
    }

    /**
     * @notice Stake WETH with compound interest and get minted shares(i.e. KKToken_Compound)(also call the stake with compound interest 'Compound Stake').
     *
     * @dev Implement the algorithm of ERC4626(a financial model of compound interest that reinvests the interest as principal to earn future interest) to calculate the amount of minted shares(i.e. KKToken_Compound).
     * A simple example which has realized ERC4626 is presented at "https://solidity-by-example.org/defi/vault/".
     * This function can stake WETH in this NFTMarket contract to earn compound interest.
     * The compound interest comes from part of the profits of selling NFT(s) which is staked(compound stake) in this NFTMarket contract automatically without calling this function.
     * After the stake, `msg.sender` will obtain an amount of shares. Those shares can be burnt to withdraw the staked principal and its interest back.
     * Emits the event {WETHStaked_CompoundStake}.
     *
     * @param _stakedAmount the staked amount of WETH
     */
    function stakeWETH_CompoundStake(uint256 _stakedAmount) public {
        if (_stakedAmount == 0) {
            revert stakeZero();
        }
        uint256 shares;
        uint256 totalSupply = KKToken(KKToken_Compound).totalSupply();
        if (totalSupply == 0) {
            shares = _stakedAmount;
        } else {
            shares = (_stakedAmount * totalSupply) / stakePool_CompoundStake;
        }
        IWETH9(wrappedETHAddr).transferFrom(msg.sender, address(this), _stakedAmount);
        KKToken(KKToken_Compound).mint(msg.sender, shares);
        stakePool_CompoundStake += _stakedAmount;
        emit WETHStaked_CompoundStake(msg.sender, _stakedAmount, shares);
    }

    /**
     * @notice This function is used for unstaking WETH. Burn KKToken_Compound(shares) to fetch back staked WETH with the interest of staking.
     *
     * @dev Using the algorithm of ERC4626(a financial model of compound interest and re-invest) to calculate the amount of burnt shares(i.e. KKToken_Compound).
     * A simple example which has realized ERC4626 is presented at "https://solidity-by-example.org/defi/vault/".
     * After the execution of this function, the unstaked principal and its interest will be still in this contract, but the WETH balance of `msg.sender`(i.e. userBalanceOfWETH[msg.sender]) will updated.
     * User can call {withdrawFromWETHBalance} to get their principal and earned interest back in the form of ETH.
     * Emits the event {WETHUnstaked_CompoundStake}.
     *
     * @param _sharesAmount the amount of shares that need to be burnt
     */
    function unstakeWETH_CompoundStake(uint256 _sharesAmount) public {
        if (_sharesAmount == 0) {
            revert invalidUnstakedAmount();
        }
        uint256 totalSupply = KKToken(KKToken_Compound).totalSupply();
        uint amount = (_sharesAmount * stakePool_CompoundStake) / totalSupply;
        KKToken(KKToken_Compound).burn(msg.sender, _sharesAmount);
        stakePool_CompoundStake -= amount;
        userBalanceOfWETH[msg.sender] += amount;
        emit WETHUnstaked_CompoundStake(msg.sender, _sharesAmount, amount);
    }


    // ------------------------------------------------------------ ** Stake and Unstake(Mining) ** ------------------------------------------------------------

    /**
     * @notice Stake ETH to mine.
     *
     * @dev The total staked(mining) amount of ETH will be recorded by the state variable `stakePool_Mining`.
     * This function can stake ETH in this NFTMarket contract to earn interest of mining.
     * The interest comes from the fixed amount of mining in each block.
     * In this type of stake, `miningInterestAdjusted` which represents the interest(multiplied by `MANTISSA`) of each staked ETH is maintained globally when `stakePool_Mining` changes(non-zero value of `stakePool_Mining` required).
     * Emits the event {WETHStaked_Mining}.
     */
    function stakeETH_Mining() public payable {
        uint256 _stakedAmount = msg.value;
        if (_stakedAmount == 0) {
            revert stakeZero();
        }
        // Update the interest per stake and the accrual block number
        _updateInterest_Mining();
        // Update the earned interest before updating the principal.
        // When a user stakes ETH for the first time, the principal before this stake will be zero. The earned interest of this staker is zero as well.
        staker_mining[msg.sender].earned += staker_mining[msg.sender].principal * (miningInterestAdjusted - staker_mining[msg.sender].accrualInterestAdjusted) / MANTISSA;
        // Convert the transferred ETH to WETH.
        IWETH9(wrappedETHAddr).deposit{value: _stakedAmount}();
        // Update the fields of `staker_mining`.
        staker_mining[msg.sender].principal += _stakedAmount;
        staker_mining[msg.sender].accrualInterestAdjusted = miningInterestAdjusted;
        // Add the new staked amount of WETH into `stakePool_Mining`(i.e. the total amount of the staked WETH)
        stakePool_Mining += _stakedAmount;
        emit WETHStaked_Mining(msg.sender, _stakedAmount, miningInterestAdjusted);
    }

    /**
     * @notice Stake WETH to mine.
     *
     * @dev The total staked(mining) amount of WETH will be recorded by the state variable `stakePool_Mining`.
     * This function can stake WETH in this NFTMarket contract to earn interest of mining.
     * The interest comes from the fixed amount of mining in each block.
     * In this type of stake, `miningInterestAdjusted` which represents the interest(multiplied by `MANTISSA`) of each staked WETH is maintained globally when `stakePool_Mining` changes(non-zero value of `stakePool_Mining` required).
     * Emits the event {WETHStaked_Mining}.
     *
     * @param _stakedAmount the staked amount of WETH
     */
    function stakeWETH_Mining(uint256 _stakedAmount) public {
        if (_stakedAmount == 0) {
            revert stakeZero();
        }
        // Update the interest per stake and the accrual block number
        _updateInterest_Mining();
        // Update the earned interest before updating the principal.
        // When a user stakes WETH for the first time, the principal before this stake will be zero. The earned interest of this staker is zero as well.
        staker_mining[msg.sender].earned += staker_mining[msg.sender].principal * (miningInterestAdjusted - staker_mining[msg.sender].accrualInterestAdjusted) / MANTISSA;
        // Transfer WETH from `msg.sender` to `address(this)`
        IWETH9(wrappedETHAddr).transferFrom(msg.sender, address(this), _stakedAmount);
        // Update the fields of `staker_mining`.
        staker_mining[msg.sender].principal += _stakedAmount;
        staker_mining[msg.sender].accrualInterestAdjusted = miningInterestAdjusted;
        // Add the new staked amount of WETH into `stakePool_Mining`(i.e. the total amount of the staked WETH)
        stakePool_Mining += _stakedAmount;
        emit WETHStaked_Mining(msg.sender, _stakedAmount, miningInterestAdjusted);
    }

    /**
     * @notice Unstake WETH from this NFTMarket contract(mining).
     *
     * @dev Unstake an amount of principal equivalent to `_unstakeAmount` and also get its corresponding interest back.
     * Emits the event {WETHUnstaked_Mining}.
     * 
     * @param _unstakeAmount the unstaked amount of WETH
     */
    function unstakeWETH_Mining(uint256 _unstakeAmount) public {
        if (_unstakeAmount == 0 || _unstakeAmount > staker_mining[msg.sender].principal) {
            revert invalidUnstakedAmount();
        }
        // Update the interest per stake and the accrual block number
        _updateInterest_Mining();
        // Update the earned interest before updating the principal.
        staker_mining[msg.sender].earned += staker_mining[msg.sender].principal * (miningInterestAdjusted - staker_mining[msg.sender].accrualInterestAdjusted) / MANTISSA;
        // Calculate the earned interest corresponding to the unstaked amount of WETH based on the proportion of `_unstakeAmount` in `staker_mining[msg.sender].principal`(before minus by `_unstakeAmount`).
        uint256 correspondingInterest = _unstakeAmount * staker_mining[msg.sender].earned / staker_mining[msg.sender].principal;
        // Calculate the total amount of withdrawn WETH
        userBalanceOfWETH[msg.sender] += _unstakeAmount;
        // transfer the profit of mining(i.e. KKToken) to `msg.sender`.
        KKToken(KKToken_Mining).transfer(msg.sender, correspondingInterest);
        // Update the fields of the unstaker after withdrawing the corresponding interest to `_unstakeAmount`.
        staker_mining[msg.sender].earned -= correspondingInterest;
        staker_mining[msg.sender].principal -= _unstakeAmount;
        staker_mining[msg.sender].accrualInterestAdjusted = miningInterestAdjusted;
        // Withdraw the unstaked amount of WETH from `stakePool_Mining`(i.e. the total amount of the staked WETH)
        stakePool_Mining -= _unstakeAmount;
        emit WETHUnstaked_Mining(msg.sender, _unstakeAmount, miningInterestAdjusted);
    }


    // ------------------------------------------------------ ** Utils ** ------------------------------------------------------

    /**
     * @notice Change the owner of this NFTMarket contract by the current owner.
     *
     * @dev Replace the value stored of the slot which records the address of the NFTMarket owner with a new address.
     * Emits the event {changeOwnerOfNFTMarket}.
     *
     * @param _newOwner the address of the new owner of the NFTMarket contract
     */
    function changeOwnerOfNFTMarket(address _newOwner) public onlyNFTMarketOwner {
        address previousOwner = owner;
        assembly {
            sstore(0, _newOwner)
        }
        emit NFTMarketOwnerChanged(previousOwner, _newOwner);
    }

    /**
     * @notice Modify the price of a listed NFT by the NFT seller.
     *
     * @dev Emits the event {NFTPriceModified}.
     *
     * @param _nftAddr the address of the contract where the NFT is located
     * @param _tokenId the tokenId of the NFT whose price is going to be modified
     * @param _newPriceInWETH the new price of the NFT
     */
    function modifyPriceForNFT(address _nftAddr, uint256 _tokenId, uint256 _newPriceInWETH) public {
        require(IERC721(_nftAddr).getApproved(_tokenId) != msg.sender, "Not seller or Not on sale");
        price[_nftAddr][_tokenId] = _newPriceInWETH;
        emit NFTPriceModified(_nftAddr, _tokenId, _newPriceInWETH);
    }


    // ------------------------------------------------------ ** Functions with View-modifier ** ------------------------------------------------------

    /**
     * @notice Check if this NFTMarket contract has been approved by a specific NFT.
     */
    function checkIfApprovedByNFT(address _nftAddr, uint256 _tokenId) public view returns (bool) {
        bool isApproved = false;
        if (IERC721(_nftAddr).getApproved(_tokenId) == address(this)) {
            isApproved = true;
        }
        return isApproved;
    }

    /**
     * @notice Get the current price of a specific NFT.
     */
    function getNFTPrice(address _nftAddr, uint256 _tokenId) public view returns (uint256) {
        return price[_nftAddr][_tokenId];
    }

    /**
     * @notice Get the WETH balance of `msg.sender` in this contract.
     */
    function getUserBalanceOfWETH() public view returns (uint256) {
        return userBalanceOfWETH[msg.sender];
    }

    /**
     * @notice Get the GTST balance of `msg.sender` in this contract.
     */
    function getUserBalanceOfGTST() public view returns (uint256) {
        return userBalanceOfGTST[msg.sender];
    }

    /**
     * @notice Get the current owner of a specific NFT.
     */
    function getNFTOwner(address _nftAddr, uint256 _tokenId) public view returns (address) {
        return IERC721(_nftAddr).ownerOf(_tokenId);
    }

    /**
     * @notice Get the owner address of this NFTMarket contract.
     *
     * @dev Load the value stored of the slot which records the address of the NFTMarket owner.
     */
    function getOwnerOfNFTMarket() public view returns (address ownerAddress) {
        assembly {
            ownerAddress := sload(0)
        }
    }

    /**
     * @notice Get the amount of the token swapped out without considering slippage.
     * 
     * @param _amountIn the exact amount of the token invested into the swap
     * @param _path a dynamic array of addresses, And each element represents the address of a unique swapped token
     */
    function getAmountsOut(uint _amountIn, address[] memory _path) public view returns (uint[] memory _amountsOut) {
        _amountsOut = IUniswapV2Router02(routerAddr).getAmountsOut(_amountIn, _path);
    }

    /**
     * @notice Get the amount of the token invested into the swap without considering slippage.
     * 
     * @param _amountOut the exact amount of the token swapped out from the swap
     * @param _path a dynamic array of addresses, And each element represents the address of a unique swapped token
     */
    function getAmountsIn(uint _amountOut, address[] memory _path) public view returns (uint[] memory _amountsIn) {
        _amountsIn = IUniswapV2Router02(routerAddr).getAmountsIn(_amountOut, _path);
    }

    /**
     * @notice Get the information about the staker which has staked(simple stake) WETH.
     *
     * @dev Get the struct which contains multiple fields including `principal`, `accrualInterestAdjusted` and `earned` of `msg.sender`.
     */
    function getStakerInfo_SimpleStake() public view returns(stakerOfSimpleStake memory) {
        return staker_simple[msg.sender];
    }

    /**
     * @notice Get the total supply of KKToken_Compound(the shares of the staked ETH).
     */
    function getTotalSupplyOfShares_CompoundStake() public view returns (uint256) {
        return KKToken(KKToken_Compound).totalSupply();
    }

    /**
     * @notice Get the total supply of KKToken_Mining.
     */
    function getTotalSupplyOfShares_Mining() public view returns (uint256) {
        return KKToken(KKToken_Mining).totalSupply();
    }

    /**
     * @notice Get the total earned of mining profit of `msg.sender`.
     */
    function pendingEarn_Mining() public view returns (uint256) {
        return staker_mining[msg.sender].earned;
    }


    // ------------------------------------------------------ ** Functions with Pure-modifier ** ------------------------------------------------------

    /**
     * @dev This function indicates that this contract supports safeTransfers of ERC-721 tokens.
     */
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        pure
        override
        returns (bytes4)
    {
        return this.onERC721Received.selector;
    }


    // ------------------------------------------------------ ** Internal Functions ** ------------------------------------------------------

    /**
     * @dev This internal function is called when an NFT is bought(except via {buyWithGTST}).
     * Part of the profit from NFT transactions will be staked.
     * Using the algorithm of ERC4626(a financial model of compound interest and re-invest) to calculate the amount of minted shares(i.e. KKToken_Compound).
     * 
     * Note The WETH to be staked has already been in this contract, so there is no need to transfer WETH from `_account` to `address(this)`.
     */
    function _stakeWETH_CompoundStake(address _account, uint256 _stakedAmount) internal {
        uint256 shares;
        uint256 totalSupply = KKToken(KKToken_Compound).totalSupply();
        if (totalSupply == 0) {
            shares = _stakedAmount;
        } else {
            shares = (_stakedAmount * totalSupply) / stakePool_CompoundStake;
        }
        KKToken(KKToken_Compound).mint(_account, shares);
        stakePool_CompoundStake += _stakedAmount;
    }

    function _verifyMerkleProof(bytes32[] memory _proof, bytes32 _root, bytes32 _leaf) internal pure {
        require(MerkleProof.verify(_proof, _root, _leaf), "Invalid Merkle proof");
    }

    function _support_IERC721Permit(address _contractAddr) internal view returns (bool) {
        bytes4 INFTPermit_Id = type(INFTPermit).interfaceId;
        IERC165 contractInstance = IERC165(_contractAddr);
        return contractInstance.supportsInterface(INFTPermit_Id);
    }

    function _support_IERC20(address _contractAddr) internal view returns (bool) {
        bytes4 IERC20_Id = type(IERC20).interfaceId;
        IERC165 contractInstance = IERC165(_contractAddr);
        return contractInstance.supportsInterface(IERC20_Id);
    }

    function _support_IERC20Permit(address _contractAddr) internal view returns (bool) {
        bytes4 IERC20Permit_Id = type(IERC20Permit).interfaceId;
        IERC165 contractInstance = IERC165(_contractAddr);
        return contractInstance.supportsInterface(IERC20Permit_Id);
    }

    function _List(address _nftAddr, uint256 _tokenId, uint256 _priceInWETH) internal {
        IERC721(_nftAddr).safeTransferFrom(msg.sender, address(this), _tokenId, "List successfully");
        IERC721(_nftAddr).approve(msg.sender, _tokenId);
        price[_nftAddr][_tokenId] = _priceInWETH;
        emit NFTListed(msg.sender, _nftAddr, _tokenId, _priceInWETH);
    }

    function _beforeNFTPurchase(address _buyer, address _ERC20TokenAddr, address _nftAddr, uint256 _tokenId)
        internal
        view
        returns (bool)
    {   
        // Check if the NFT corresponding to `_nftAddr` is already listed.
        if (price[_nftAddr][_tokenId] == 0) {
            revert notOnSale(_nftAddr, _tokenId);
        }

        // Check if the contract corresponding to `_ERC20TokenAddr` has satisfied the interface {IERC20}.
        bool isIERC20Supported = _support_IERC20(_ERC20TokenAddr);
        if (!isIERC20Supported) {
            revert notERC20Token(_ERC20TokenAddr);
        }

        // Check if the buyer is not the owner of the NFT which is desired to be bought.
        // When NFT listed, the previous owner(EOA, the seller) should be approved. So, this EOA can delist NFT whenever he/she wants.
        // After NFT is listed successfully, getApproved() will return the orginal owner of the listed NFT.
        address previousOwner = IERC721(_nftAddr).getApproved(_tokenId);
        if (_buyer == previousOwner) {
            revert ownerBuyNFTOfSelf(_nftAddr, _tokenId, _buyer);
        }

        // If everything goes well without any reverts, here comes a return boolean value. It indicates that all the checks are passed.
        return true;
    }

    /**
     * @dev This internal function only conducts the 'action' of a single NFT purchase with an exact amount of ERC-20 token used for buying an NFT.
     */
    function _handleNFTPurchase(address _nftBuyer, address _ERC20TokenAddr, address _nftAddr, uint256 _tokenId, uint256 _tokenAmount) internal returns (uint256 result) {
        uint256 NFTPrice = getNFTPrice(_nftAddr, _tokenId);

        // If the ERC-20 token used for buying NFTs is not WETH, execute token-swap.
        // To make the NFT purchase more economical, calculate the necessary(also minimal) amount of token paid based on the current price of the NFT(uint: WETH or ETH).
        if (_ERC20TokenAddr != wrappedETHAddr) {
            bool _success = IERC20(_ERC20TokenAddr).transferFrom(_nftBuyer, address(this), _tokenAmount);
            require(_success, "ERC-20 token transferFrom failed");

            // token swap
            uint256 tokenBalanceBeforeSwap = IERC20(_ERC20TokenAddr).balanceOf(address(this));
            uint256 tokenAmountPaid = _swapTokenForExactWETH(_ERC20TokenAddr, NFTPrice, _tokenAmount);
            uint256 tokenBalanceAfterSwap = IERC20(_ERC20TokenAddr).balanceOf(address(this));
            if (tokenBalanceAfterSwap >= tokenBalanceBeforeSwap || tokenBalanceBeforeSwap - tokenBalanceAfterSwap != tokenAmountPaid) {
                address[] memory _path = new address[](2);
                _path[0] = _ERC20TokenAddr;
                _path[1] = wrappedETHAddr;
                revert tokenSwapFailed(_path, NFTPrice, _tokenAmount);
            }

            // After paying the necessary amount of token, refund excess amount.
            uint256 refundTokenAmount = _tokenAmount - tokenAmountPaid;
            bool _refundTokenSuccess = IERC20(_ERC20TokenAddr).transfer(_nftBuyer, refundTokenAmount);
            require(_refundTokenSuccess, "Fail to refund exceed amount of token");
            result = tokenAmountPaid;
        } else {
            bool _ok = IWETH9(wrappedETHAddr).transferFrom(_nftBuyer, address(this), NFTPrice);
            require(_ok, "WETH transferFrom failed");
            result = NFTPrice;
        }
        // Execute the transfer of the NFT being bought
        IERC721(_nftAddr).transferFrom(address(this), _nftBuyer, _tokenId);

        // Stake WETH
        address NFTOwner = IERC721(_nftAddr).getApproved(_tokenId);
        // Method 1: simple interest
        uint256 stakedAmount_Simple;
        // If `stakePool_SimpleStake` equals 0, the simple stake will be skipped, or the interest will be updated.
        if (stakePool_SimpleStake != 0) {
            stakedAmount_Simple = NFTPrice * FIGURE_FEERATIO / (10 ** FRACTION_FEERATIO);
            _updateInterest_SimpleStake(stakedAmount_Simple);
        }

        // Method 2: compound interest
        uint256 stakedAmount_Compound = NFTPrice * FIGURE_FEERATIO / (10 ** FRACTION_FEERATIO);
        _stakeWETH_CompoundStake(NFTOwner, stakedAmount_Compound);

        // Add the earned amount of WETH(i.e. the price of the sold NFT) to the balance of the NFT seller.
        userBalanceOfWETH[NFTOwner] += NFTPrice - stakedAmount_Simple - stakedAmount_Compound;

        // Reset the price of the sold NFT. This indicates that this NFT is not on sale.
        delete price[_nftAddr][_tokenId];
    }

    /**
     * @dev This internal function only conducts the 'action' of a single NFT purchase with an exact amount of ERC-20 token used for buying an NFT.
     * And User should consider the slippage for token-swap.
     */
    function _handleNFTPurchaseWithSlippage(address _nftBuyer, address _ERC20TokenAddr, address _nftAddr, uint256 _tokenId, uint256 _slippageFigure, uint256 _slippageFraction) internal returns (uint256 result) {
        uint256 NFTPrice = getNFTPrice(_nftAddr, _tokenId);
    
        // If the ERC-20 token used for buying NFTs is not WETH, execute token-swap.
        // To make the NFT purchase more economical, calculate the necessary(also minimal) amount of token paid based on the current price of the NFT(uint: WETH or ETH).
        if (_ERC20TokenAddr != wrappedETHAddr) {
            uint256 amountInRequired = _estimateAmountInWithSlipage(_ERC20TokenAddr, NFTPrice, _slippageFigure, _slippageFraction);
            bool _success = IERC20(_ERC20TokenAddr).transferFrom(_nftBuyer, address(this), amountInRequired);
            require(_success, "ERC-20 token transferFrom failed");

            // token swap
            uint256 tokenBalanceBeforeSwap = IERC20(_ERC20TokenAddr).balanceOf(address(this));
            uint256 tokenAmountPaid = _swapTokenForExactWETH(_ERC20TokenAddr, NFTPrice, amountInRequired);
            uint256 tokenBalanceAfterSwap = IERC20(_ERC20TokenAddr).balanceOf(address(this));
            if (tokenBalanceAfterSwap >= tokenBalanceBeforeSwap || tokenBalanceBeforeSwap - tokenBalanceAfterSwap != tokenAmountPaid) {
                address[] memory _path = new address[](2);
                _path[0] = _ERC20TokenAddr;
                _path[1] = wrappedETHAddr;
                revert tokenSwapFailed(_path, NFTPrice, amountInRequired);
            }
            result = tokenAmountPaid;
        } else {
            bool _ok = IWETH9(wrappedETHAddr).transferFrom(_nftBuyer, address(this), NFTPrice);
            require(_ok, "WETH transferFrom failed");
            result = NFTPrice;
        }
        // Execute the transfer of the NFT being bought
        IERC721(_nftAddr).transferFrom(address(this), _nftBuyer, _tokenId);
        
        // Stake WETH
        address NFTOwner = IERC721(_nftAddr).getApproved(_tokenId);
        // Method 1: simple interest
        uint256 stakedAmount_Simple;
        // If `stakePool_SimpleStake` equals 0, the simple stake will be skipped, or the interest will be updated.
        if (stakePool_SimpleStake != 0) {
            stakedAmount_Simple = NFTPrice * FIGURE_FEERATIO / (10 ** FRACTION_FEERATIO);
            _updateInterest_SimpleStake(stakedAmount_Simple);
        }

        // Method 2: compound interest
        uint256 stakedAmount_Compound = NFTPrice * FIGURE_FEERATIO / (10 ** FRACTION_FEERATIO);
        _stakeWETH_CompoundStake(NFTOwner, stakedAmount_Compound);

        // Add the earned amount of WETH(i.e. the price of the sold NFT) to the balance of the NFT seller.
        userBalanceOfWETH[NFTOwner] += NFTPrice - stakedAmount_Simple - stakedAmount_Compound;

        // Reset the price of the sold NFT. This indicates that this NFT is not on sale.
        delete price[_nftAddr][_tokenId];
    }

    /**
     * @dev This internal function only conducts the 'action' of a single NFT purchase using an exact amount of GTST.
     * And User should consider the slippage for token-swap.
     */
    function _handleNFTPurchaseUsingGTST(address _nftBuyer, address _nftAddr, uint256 _tokenId, uint256 _tokenAmount) internal {
        bool _success = IERC20(GTSTAddr).transferFrom(_nftBuyer, address(this), _tokenAmount);
        require(_success, "Fail to buy or Allowance is insufficient");
        // Execute the transfer of the NFT being bought
        IERC721(_nftAddr).transferFrom(address(this), _nftBuyer, _tokenId);
        // Add the earned amount of WETH(i.e. the price of the sold NFT) to the balance of the NFT seller.
        userBalanceOfGTST[IERC721(_nftAddr).getApproved(_tokenId)] += _tokenAmount;
        // Reset the price of the sold NFT. This indicates that this NFT is not on sale.
        delete price[_nftAddr][_tokenId];
    }

    function _swapExactTokenForWETH(address _ERC20TokenAddr, uint256 _amountIn, uint256 _amountOutMin) internal returns (uint256) {
        address[] memory _path = new address[](2);
        _path[0] = _ERC20TokenAddr;
        _path[1] = wrappedETHAddr;
        uint256 _deadline = block.timestamp + 600;
        uint[] memory amountsOut = IUniswapV2Router02(routerAddr).swapExactTokensForTokens(_amountIn, _amountOutMin, _path, address(this), _deadline);
        return amountsOut[_path.length - 1];
    }

    function _swapTokenForExactWETH(address _ERC20TokenAddr, uint256 _amountOut, uint256 _amountInMax) internal returns (uint256) {
        address[] memory _path = new address[](2);
        _path[0] = _ERC20TokenAddr;
        _path[1] = wrappedETHAddr;
        uint256 _deadline = block.timestamp + 600;
        uint[] memory amountsIn = IUniswapV2Router02(routerAddr).swapTokensForExactTokens(_amountOut, _amountInMax, _path, address(this), _deadline);
        return amountsIn[0];
    }

    function _estimateAmountInWithSlipage(address _ERC20TokenAddr, uint256 _amountOut, uint256 _slippageFigure, uint256 _slippageFraction) internal returns (uint256) {
        address[] memory _path = new address[](2);
        _path[0] = _ERC20TokenAddr;
        _path[1] = wrappedETHAddr;
        if (_slippageFigure == 0 ||  _slippageFraction == 0) {
            revert invalidSlippage(_slippageFigure, _slippageFraction);
        }
        uint256 amountInWithoutSlippage = getAmountsIn(_amountOut, _path)[0];
        uint256 amountInWithSlippage = amountInWithoutSlippage * (10 ** _slippageFraction +  _slippageFigure) / (10 ** _slippageFraction);
        return amountInWithSlippage;
    }

    function _updateInterest_SimpleStake(uint256 _value) internal {
        if (stakePool_SimpleStake != 0) {
            stakeInterestAdjusted += _value * MANTISSA / stakePool_SimpleStake;
        }
    }

    function _updateInterest_Mining() internal {
        // Initialization of a zero-stake pool
        if (stakePool_Mining == 0) {
            miningInterestAdjusted = 0;
            BlockNumberLast = block.number;
        }
        // If the last block number used to update the interest is not equal to the current block number, calculate the interest as follows
        if (block.number != BlockNumberLast && stakePool_Mining != 0) {
            KKToken(KKToken_Mining).mint(address(this), minedAmountPerBlock * (block.number - BlockNumberLast));
            miningInterestAdjusted += (block.number - BlockNumberLast) * minedAmountPerBlock * MANTISSA / stakePool_Mining;
            BlockNumberLast = block.number;
        }
    }

}
