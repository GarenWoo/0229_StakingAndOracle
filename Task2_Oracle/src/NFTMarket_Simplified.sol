//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC721} from"@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/INFTMarket_Simplified.sol";
import "./interfaces/AggregatorV3Interface.sol";
import {UniswapV2Router02} from "./Uniswap_v2_periphery/UniswapV2Router02.sol";
import {UniswapV2Library} from "./Uniswap_v2_periphery/libraries/UniswapV2Library.sol";

/**
 * @title This is an NFT exchange contract that can provide trading for ERC721 Tokens. Various ERC721 tokens are able to be traded here.
 * This contract was updated from `NFTMarket_V5`.
 *
 * @author Garen Woo
 */
contract NFTMarket_Simplified is INFTMarket_Simplified, IERC721Receiver {
    using SafeERC20 for IERC20;
    address private owner;                              // the address of the owner of this NFTMarket contract
    address public immutable GTSTAddr;                  // the address of the default ERC-20 token used in trading NFT(s) in this NFTMarket
    address public immutable wrappedETHAddr;            // the address of WETH
    address public immutable routerAddr;                // the address of Uniswap_v2_Router02 which provides swap between multiple types of tokens
    mapping(address NFTAddr => mapping(uint256 tokenId => uint256 priceInETH)) private price;       // the price of a specific NFT which is set at the moment of listing.
    mapping(address user => uint256 GTSTBalance) private userBalanceOfGTST;     // the GTST balance of a specific user
    AggregatorV3Interface internal priceFeedAggregator;

    constructor(address _tokenAddr, address _wrappedETHAddr, address _routerAddr, address _priceFeedAggregatorAddr) {
        owner = msg.sender;
        GTSTAddr= _tokenAddr;
        wrappedETHAddr = _wrappedETHAddr;
        routerAddr = _routerAddr;
        priceFeedAggregator = AggregatorV3Interface(_priceFeedAggregatorAddr);
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
     * 3. The listed NFT will be flagged with `_price` which is the price counted in the minimum unit of WETH.
     * 4. Emits the event {NFTListed}.
     *
     * @param _nftAddr the address of the contract where the NFT is located
     * @param _tokenId the tokenId of the NFT which is aimed to be listed by `msg.sender`
     * @param _price the amount of WETH(counted in the minimum unit of WETH) representing the price of the listed NFT
     */
    function list(address _nftAddr, uint256 _tokenId, uint256 _price) external {
        if (msg.sender != IERC721(_nftAddr).ownerOf(_tokenId)) {
            revert notOwnerOfNFT();
        }
        if (_price == 0) revert zeroPrice();
        require(price[_nftAddr][_tokenId] == 0, "This NFT is already listed");
        _List(_nftAddr, _tokenId, _price);
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
     * @notice Buy an NFT using GTST(a specific ERC20-token used in this NFTMarket). 
     * The amount of paid GTST should not less than the price of the NFT under purchase.
     * All the given GTST will be spent on buying the NFT without refunding the excess.
     *
     * @dev After the NFT purchase, the GTST balance of the NFT seller will increase by `_tokenAmount`.
     * Emits the event {NFTBoughtWithGTST}.
     *
     * @param _nftAddr the address of the contract where the NFT the buyer wants to buy is located
     * @param _tokenId the tokenId of the NFT which is aimed to be bought.
     * @param _tokenAmount the amount of paid "GTST"
     */
    function buy(address _nftAddr, uint256 _tokenId, uint256 _tokenAmount) external {
        bool checkResult = _beforeNFTPurchase(msg.sender, GTSTAddr, _nftAddr, _tokenId);
        
        // If all the checks have passed, here comes the execution of the NFT purchase.
        if (checkResult) {
            _handleNFTPurchaseUsingGTST(msg.sender, _nftAddr, _tokenId, _tokenAmount);
            emit NFTBoughtWithGTST(msg.sender, _nftAddr, _tokenId, _tokenAmount);
        }
    }


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
    function withdrawFromGTSTBalance(uint256 _value) external {
        if (_value > userBalanceOfGTST[msg.sender]) {
            revert withdrawalExceedBalance(_value, userBalanceOfGTST[msg.sender]);
        }
        userBalanceOfGTST[msg.sender] -= _value;
        bool _success = IERC20(GTSTAddr).transfer(msg.sender, _value);
        require(_success, "withdraw GTST failed");
        emit GTSTWithdrawn(msg.sender, _value);
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
     * @notice Get the latest price of ETH/USD.
     */
    function getLatestPrice_ETH_USD() public view returns (uint80 _roundId, int256 _price, uint256 _updatedAt) {
        (
            _roundId,
            _price,
            /*uint256 startedAt*/,
            _updatedAt,
            /*uint80 answeredInRound*/
        ) = priceFeedAggregator.latestRoundData();
    }

    /**
     * @notice Get the price of ETH/USD in a specific round.
     */
    function getPriceOfRound(uint80 _roundId) public view returns (int256 _price, uint256 _updatedAt) {
        (
            /*uint80 roundId*/,
            _price,
            /*uint256 startedAt*/,
            _updatedAt,
            /*uint80 answeredInRound*/
        ) = priceFeedAggregator.getRoundData(_roundId);
    }

    /**
     * @notice Get the current reserves of GTST and WETH respectively.
     */
    function getReserves_GTST_WETH() public view returns(uint reserveA, uint reserveB) {
        address factoryAddr = UniswapV2Router02(payable(routerAddr)).factory();
        (reserveA, reserveB) = UniswapV2Library.getReserves(factoryAddr, GTSTAddr, wrappedETHAddr);
    }

    function getNFTPrice_CountedInWETH(address _NFTAddr, uint256 _tokenId) public view returns (uint256) {
        uint256 priceInGTST = price[_NFTAddr][_tokenId];
        (uint256 reserve_GTST, uint256 reserve_WETH) = getReserves_GTST_WETH();
        require(reserve_WETH != 0, "Reserve of WETH is 0");
        uint256 priceInWETH = (priceInGTST * reserve_WETH) / reserve_GTST;
        return priceInWETH;
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

    function _support_IERC20(address _contractAddr) internal view returns (bool) {
        bytes4 IERC20_Id = type(IERC20).interfaceId;
        IERC165 contractInstance = IERC165(_contractAddr);
        return contractInstance.supportsInterface(IERC20_Id);
    }

    function _List(address _nftAddr, uint256 _tokenId, uint256 _price) internal {
        IERC721(_nftAddr).safeTransferFrom(msg.sender, address(this), _tokenId, "List successfully");
        IERC721(_nftAddr).approve(msg.sender, _tokenId);
        price[_nftAddr][_tokenId] = _price;
        emit NFTListed(msg.sender, _nftAddr, _tokenId, _price);
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

}
