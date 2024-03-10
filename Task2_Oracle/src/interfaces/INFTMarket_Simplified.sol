//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title An interface for NFT Market.
 *
 * @author Garen Woo
 */
interface INFTMarket_Simplified {

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
    event NFTBoughtWithGTST(address indexed user, address indexed NFTAddr, uint256 indexed tokenId, uint256 tokenPaid);

    /**
     *  @dev Emitted when a user withdraw GTST from its WETH balance in the NFTMarket contract.
     */
    event GTSTWithdrawn(address withdrawer, uint256 withdrawnValue);

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
     * @dev Indicates a failure when detecting a contract does not satisfy the interface {IERC20}
     */
    error notERC20Token(address inputAddress);

    /**
     * @dev Indicates a failure when the owner of an NFT attempts to buy the NFT.
     */
    error ownerBuyNFTOfSelf(address NFTAddr, uint256 tokenId, address user);

    
    // ------------------------------------------------------ ** List / Delist NFT ** ------------------------------------------------------
     
    /**
     * @notice List an NFT by its owner. This will allow the NFT to be bought by other users.
     *
     * @dev Once the NFT is listed, there will be multiple operations occur:
     * 1. The NFT will be transferred from `msg.sender` to `address(this)`. The actual owner of the NFT will be `address(this)` after this transfer.
     * 2. The NFT seller(also the previous owner of the NFT, i.e. `msg.sender`) will be approved to operate the NFT considering the operability of the NFT seller(e.g. the seller can delist its NFT at any time).
     * 3. The listed NFT will be flagged with `_price` which is the price counted in the minimum unit of WETH.
     * 4. Emits the event {NFTListed}.
     *
     * @param _nftAddr the address of the contract where the NFT is located
     * @param _tokenId the tokenId of the NFT which is aimed to be listed by `msg.sender`
     * @param _price the amount of WETH(counted in the minimum unit of WETH) representing the price of the listed NFT
     */
    function list(address _nftAddr, uint256 _tokenId, uint256 _price) external;

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
    function buy(address _nftAddr, uint256 _tokenId, uint256 _tokenAmount) external;


    // ------------------------------------------------------ ** Withdrawal GTST ** ------------------------------------------------------

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

}
