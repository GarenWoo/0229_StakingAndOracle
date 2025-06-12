//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title An interface for NFT Market.
 *
 * @author Garen Woo
 */
interface INFTMarket_V5_1 {
    // ------------------------------------------------------ ** Structs ** ------------------------------------------------------

    /**
     * @dev A custom struct to define the fields of a unique function call which is used in multicall(see the function {aggregate}).
     */
    struct Call {
        address target;
        bytes callData;
    }

    /**
     * @dev A custom struct to contains the fields related to stakers of simple-stake(simple interest model).
     */
    struct stakerOfSimpleStake {
        uint256 principal;                      // the total amount of staked WETH
        uint256 accrualInterestAdjusted;        // the latestly updated interest(gloabally maintained interest of each stake) of the staker multiplied by MANTISSA
        uint256 earned;                         // the total amount of earned value
    }

    /**
     * @dev A custom struct to contains the fields related to stakers of mining.
     */
    struct stakerOfMining {
        uint256 principal;                      // the total amount of staked WETH
        uint256 accrualInterestAdjusted;        // the latestly updated interest(gloabally maintained interest of each stake) of the staker multiplied by MANTISSA
        uint256 earned;                         // the total amount of earned value
    }


    // ------------------------------------------------------ ** Events ** ------------------------------------------------------

    /**
     * @dev Emitted when a user sends ETH to this contract.
     */
    event ETHReceived(address user, uint256 value);
    
    /**
     * @dev Emitted when an NFT is listed successfully.
     */
    event NFTListed(address indexed user, address indexed NFTAddr, uint256 indexed tokenId, uint256 price);

    /**
     * @dev Emitted when an NFT is delisted successfully.
     */
    event NFTDelisted(address user, address NFTAddr, uint256 tokenId);

    /**
     * @dev Emitted when an NFT is bought successfully by a non-owner user.
     */
    event NFTBoughtWithAnyToken(address indexed user, address erc20TokenAddr, address indexed NFTAddr, uint256 indexed tokenId, uint256 tokenPaid);

    /**
     * @dev Emitted when an NFT is bought successfully by a non-owner user.
     */
    event NFTBoughtWithGTST(address indexed user, address indexed NFTAddr, uint256 indexed tokenId, uint256 tokenPaid);

    /**
     * @dev Emitted when an NFT is bought successfully by a non-owner user with an off-chain signed message in the input form of v, r, s.
     */
    event NFTBoughtWithPermit(address indexed user, address erc20TokenAddr, address indexed NFTAddr, uint256 indexed tokenId, uint256 bidValue);

    /**
     * @dev Emitted when a user withdraw WETH from its WETH balance in the NFTMarket contract.
     */
    event ETHWithdrawn(address withdrawer, uint256 withdrawnValue);

    /**
     *  @dev Emitted when a user withdraw GTST from its WETH balance in the NFTMarket contract.
     */
    event GTSTWithdrawn(address withdrawer, uint256 withdrawnValue);

    /**
     * @dev Emitted when successfully validating the signed message of the ERC2612 token owner desired to buy NFTs.
     */
    event prepay(address tokenOwner, uint256 tokenAmount);

    /**
     * @dev Emitted when an member of whitelist claims NFT successfully.
     */
    event NFTClaimed(address NFTAddr, uint256 tokenId, address user);

    /**
     * @dev Emitted when a user stakes(simple interest) WETH in the NFTMarket contract.
     */
    event WETHStaked_SimpleStake(address user, uint256 stakedAmount, uint256 stakeInterestAdjusted);

    /**
     * @dev Emitted when a user unstakes(simple interest) WETH from the NFTMarket contract.
     */
    event WETHUnstaked_SimpleStake(address user, uint256 unstakedAmount, uint256 stakeInterestAdjusted);

    /**
     * @dev Emitted when a user stakes(compound interest) WETH in the NFTMarket contract.
     */
    event WETHStaked_CompoundStake(address user, uint256 stakedWETH, uint256 mintedShares);

    /**
     * @dev Emitted when a user unstakes(compound interest) WETH from the NFTMarket contract.
     */
    event WETHUnstaked_CompoundStake(address user, uint256 burntShares, uint256 WETHAmount);

    /**
     * @dev Emitted when a user stakes(mining) WETH in the NFTMarket contract.
     */
    event WETHStaked_Mining(address user, uint256 stakedAmount, uint256 stakeInterestAdjusted);

    /**
     * @dev Emitted when a user unstakes(mining) WETH from the NFTMarket contract.
     */
    event WETHUnstaked_Mining(address user, uint256 unstakedAmount, uint256 stakeInterestAdjusted);

    /**
     * @dev Emitted when the owner of the NFTMarket contract is replaced with a new address.
     */
    event NFTMarketOwnerChanged(address previousOwner, address newOwner);

    /**
     * @dev Emitted when the NFT seller has modified the price of its listed NFT
     */
    event NFTPriceModified(address NFTAddr, uint256 tokenId, uint256 newPrice);


    // ------------------------------------------------------ ** Errors ** ------------------------------------------------------
    
    /**
     * @dev Indicates a failure when listing an NFT. Used in checking the price set of an NFT.
     */
    error zeroPrice();

    /**
     * @dev Indicates a failure when an NFT is operated by a non-owner user. Used in checking the ownership of the NFT listed in NFTMarket.
     */
    error notOwnerOfNFT();

    /**
     * @dev Indicates a failure when checking `msg.sender` equals the owner of the NFTMarket
     */
    error notOwnerOfNFTMarket();

    /**
     * @dev Indicates a failure when a user attempts to buy or delist an NFT. Used in checking if the NFT has been already listed in the NFTMarket.
     */
    error notOnSale(address tokenAddress, uint256 tokenId);

    /**
     * @dev Indicates a failure when an NFT seller attempts to withdraw an over-balance amount of tokens from its balance.
     */
    error withdrawalExceedBalance(uint256 withdrawAmount, uint256 balanceAmount);

    /**
     * @dev Indicates a failure when a user attempts to buy an NFT by calling a function without inputting a signed message.
     * Used in checking if the user calls the valid function to avoid abuse of the function {buy}.
     */
    error ERC721PermitBoughtByWrongFunction(string calledFunction, string validFunction);

    /**
     * @dev Indicates a failure when calling the function {aggregate}.
     */
    error multiCallFail(uint256 index, bytes callData);

    /**
     * @dev Indicates a failure when detecting a contract does not satisfy the interface {IERC20}
     */
    error notERC20Token(address inputAddress);

    /**
     * @dev Indicates a failure when detecting a contract does not satisfy the interface {IERC20Permit}
     */
    error notERC20PermitToken(address inputAddress);

    /**
     * @dev Indicates a failure when the owner of an NFT attempts to buy the NFT.
     */
    error ownerBuyNFTOfSelf(address NFTAddr, uint256 tokenId, address user);

    /**
     * @dev Indicates a failure when the balance change of the ERC-20 token used for buying NFTs does not fit the returned value of functions for swap in the router contract.
     */
    error tokenSwapFailed(address[] _path, uint256 exactAmountOut, uint256 amountInMax);

    /**
     * @dev Indicates a failure when a wrong slippage is set by a user. 
     */
    error invalidSlippage(uint256 inputLiteral, uint256 inputDecimal);

    /**
     * @dev Indicates a failure when user attempts to stake 0 WETH. Using for checking the input amount of the staked WETH.
     */
    error stakeZero();

    /**
     * @dev Indicates a failure when user attempts to unstake WETH. Using for checking if the unstaked amount is zero or exceeds the total staked amount of the stake. 
     */
    error invalidUnstakedAmount();

    
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
    function list(address _nftAddr, uint256 _tokenId, uint256 _priceInWETH) external;

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
    function listWithPermit(address _nftAddr, uint256 _tokenId, uint256 _priceInWETH, uint256 _deadline, uint8 _v, bytes32 _r, bytes32 _s) external;

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
    function delist(address _nftAddr, uint256 _tokenId) external;


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
    function tokensReceived(address _recipient, address _ERC20TokenAddr, uint256 _tokenAmount, bytes calldata _data) external;
    
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
    function buyWithGTST(address _nftAddr, uint256 _tokenId, uint256 _tokenAmount) external;

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
    function buyNFTWithAnyToken(address _ERC20TokenAddr, address _nftAddr, uint256 _tokenId, uint256 _slippageFigure, uint256 _slippageFraction) external;

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
    ) external;


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
    function withdrawFromWETHBalance(uint256 _value) external;

    /**
     * @notice Withdraw a custom amount of GTST from the user's GTST balance.
     *
     * @dev `msg.sender` withdraws GTST from its GTST balance in this NFTMarket contract.
     * Transfer GTST from `address(this)` to `msg.sender` of this function.
     * Emits the event {GTSTWithdrawn}.
     *
     * @param _value the withdrawn amount of GTST
     */
    function withdrawFromGTSTBalance(uint256 _value) external;


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
    function permitPrePay(address _ERC20TokenAddr, address _tokenOwner, uint256 _tokenAmount, uint256 _deadline, uint8 _v, bytes32 _r, bytes32 _s) external returns (bool);

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
    function claimNFT(address _recipient, uint256 _promisedTokenId, bytes32[] memory _merkleProof, uint256 _promisedPriceInETH, bytes memory _NFTWhitelistData) external;


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
    function aggregate(Call[] memory _calls) external returns(bytes[] memory returnData);


    // ------------------------------------------------------ ** Stake WETH(Simple Interest) ** ------------------------------------------------------

    /**
     * @notice Stake ETH with simple interest(also call the stake with simple interest 'Simple Stake').
     *
     * @dev The total staked(simple stake) amount of ETH will be recorded(in the form of WETH) by the state variable `stakePool_SimpleStake`.
     * This function can stake ETH in this NFTMarket contract to earn simple interest.
     * The simple interest comes from part of the profits of selling NFT(s) which is automatically added to `stakePool_SimpleStake`(non-zero value of `stakePool_SimpleStake` required).
     * In this type of stake, `stakeInterestAdjusted` which represents the interest(multiplied by `MANTISSA`) of each staked ETH is maintained globally when `stakePool_SimpleStake` changes(non-zero value of `stakePool_SimpleStake` required).
     * Emits the event {WETHStaked_SimpleStake}.
     */
    function stakeETH_SimpleStake() external payable;
    
    /**
     * @notice Stake WETH with simple interest(also call the stake with simple interest 'Simple Stake').
     *
     * @dev The total staked(simple stake) amount of WETH will be recorded by the state variable `stakePool_SimpleStake`.
     * This function can stake WETH in this NFTMarket contract to earn simple interest.
     * The simple interest comes from part of the profits of selling NFT(s) which is automatically added to `stakePool_SimpleStake`(non-zero value of `stakePool_SimpleStake` required).
     * In this type of stake, `stakeInterest` which represents the interest of each staked WETH is maintained globally when `stakePool_SimpleStake` changes(non-zero value of `stakePool_SimpleStake` required).
     * Emits the event {WETHStaked_SimpleStake}.
     *
     * @param _stakedAmount the staked amount of WETH
     */
    function stakeWETH_SimpleStake(uint256 _stakedAmount) external;

    /**
     * @notice Unstake WETH from this NFTMarket contract(simple stake).
     *
     * @dev Unstake an amount of principal equivalent to `_unstakeAmount` and also get its corresponding interest back.
     * Emits the event {WETHUnstaked_SimpleStake}.
     * 
     * @param _unstakeAmount the unstaked amount of WETH
     */
    function unstakeWETH_SimpleStake(uint256 _unstakeAmount) external;


    // -------------------------------------------------- ** Stake WETH(Compound Interest, Using ERC4626) ** --------------------------------------------------

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
    function stakeETH_CompoundStake() external payable;

    /**
     * @notice Stake WETH with compound interest and get minted shares(i.e. KKToken_CompoundStake)(also call the stake with compound interest 'Compound Stake').
     *
     * @dev Implement the algorithm of ERC4626(a financial model of compound interest that reinvests the interest as principal to earn future interest) to calculate the amount of minted shares(i.e. KKToken_CompoundStake).
     * A simple example which has realized ERC4626 is presented at "https://solidity-by-example.org/defi/vault/".
     * This function can stake WETH in this NFTMarket contract to earn compound interest.
     * The compound interest comes from part of the profits of selling NFT(s) which is staked(compound stake) in this NFTMarket contract automatically without calling this function.
     * After the stake, `msg.sender` will obtain an amount of shares. Those shares can be burnt to withdraw the staked principal and its interest back.
     * Emits the event {WETHStaked_CompoundStake}.
     *
     * @param _stakedAmount the staked amount of WETH
     */
    function stakeWETH_CompoundStake(uint256 _stakedAmount) external;

    /**
     * @notice This function is used for unstaking WETH. Burn KKToken_CompoundStake(shares) to fetch back staked WETH with the interest of staking.
     *
     * @dev Using the algorithm of ERC4626(a financial model of compound interest and re-invest) to calculate the amount of burnt shares(i.e. KKToken_CompoundStake).
     * A simple example which has realized ERC4626 is presented at "https://solidity-by-example.org/defi/vault/".
     * After the execution of this function, the unstaked principal and its interest will be still in this contract, but the WETH balance of `msg.sender`(i.e. userBalanceOfWETH[msg.sender]) will updated.
     * User can call {withdrawFromWETHBalance} to get their principal and earned interest back in the form of ETH.
     * Emits the event {WETHUnstaked_CompoundStake}.
     *
     * @param _sharesAmount the amount of shares that need to be burnt
     */
    function unstakeWETH_CompoundStake(uint256 _sharesAmount) external;


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
    function stakeETH_Mining() external payable;

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
    function stakeWETH_Mining(uint256 _stakedAmount) external;

    /**
     * @notice Unstake WETH from this NFTMarket contract(mining).
     *
     * @dev Unstake an amount of principal equivalent to `_unstakeAmount` and also get its corresponding interest back.
     * Emits the event {WETHUnstaked_Mining}.
     * 
     * @param _unstakeAmount the unstaked amount of WETH
     */
    function unstakeWETH_Mining(uint256 _unstakeAmount) external;


    // ------------------------------------------------------ ** Utils ** ------------------------------------------------------

    /**
     * @notice Change the owner of this NFTMarket contract by the current owner.
     *
     * @dev Replace the value stored of the slot which records the address of the NFTMarket owner with a new address.
     * Emits the event {changeOwnerOfNFTMarket}.
     *
     * @param _newOwner the address of the new owner of the NFTMarket contract
     */
    function changeOwnerOfNFTMarket(address _newOwner) external;

    /**
     * @notice Modify the price of a listed NFT by the NFT seller.
     *
     * @dev Emits the event {NFTPriceModified}.
     *
     * @param _nftAddr the address of the contract where the NFT is located
     * @param _tokenId the tokenId of the NFT whose price is going to be modified
     * @param _newPriceInWETH the new price of the NFT
     */
    function modifyPriceForNFT(address _nftAddr, uint256 _tokenId, uint256 _newPriceInWETH) external;
    

    // ------------------------------------------------------ ** Functions with View-modifier ** ------------------------------------------------------

    /**
     * @notice Check if this NFTMarket contract has been approved by a specific NFT.
     */
    function checkIfApprovedByNFT(address _nftAddr, uint256 _tokenId) external view returns (bool);

    /**
     * @notice Get the current price of a specific NFT.
     */
    function getNFTPrice(address _nftAddr, uint256 _tokenId) external view returns (uint256);

    /**
     * @notice Get the WETH balance of `msg.sender` in this contract.
     */
    function getUserBalanceOfWETH() external view returns (uint256);

    /**
     * @notice Get the GTST balance of `msg.sender` in this contract.
     */
    function getUserBalanceOfGTST() external view returns (uint256);

    /**
     * @notice Get the owner of a specific NFT.
     */
    function getNFTOwner(address _nftAddr, uint256 _tokenId) external view returns (address);

    /**
     * @notice Get the owner address of this NFTMarket contract.
     *
     * @dev Load the value stored of the slot which records the address of the NFTMarket owner.
     */
    function getOwnerOfNFTMarket() external view returns (address ownerAddress);

    /**
     * @notice Get the amount of the token swapped out without considering slippage.
     * 
     * @param _amountIn the exact amount of the token invested into the swap
     * @param _path a dynamic array of addresses, And each element represents the address of a unique swapped token
     */
    function getAmountsOut(uint _amountIn, address[] memory _path) external view returns (uint[] memory _amountsOut);

    /**
     * @notice Get the amount of the token invested into the swap without considering slippage.
     * 
     * @param _amountOut the exact amount of the token swapped out from the swap
     * @param _path a dynamic array of addresses, And each element represents the address of a unique swapped token
     */
    function getAmountsIn(uint _amountOut, address[] memory _path) external view returns (uint[] memory _amountsIn);

    /**
     * @notice Get the information about the staker which has staked(simple stake) WETH.
     *
     * @dev Get the struct which contains multiple fields including `principal`, `accrualInterest` and `earned` of `msg.sender`.
     */
    function getStakerInfo_SimpleStake() external view returns(stakerOfSimpleStake memory);

    /**
     * @notice Get the total supply of KKToken_CompoundStake(the shares of the staked ETH).
     */
    function getTotalSupplyOfShares_CompoundStake() external view returns (uint256);

    /**
     * @notice Get the total supply of KKToken_Mining.
     */
    function getTotalSupplyOfShares_Mining() external view returns (uint256);

    /**
     * @notice Get the total earned of mining profit of `msg.sender`.
     */
    function pendingEarn_Mining() external view returns (uint256);

}
