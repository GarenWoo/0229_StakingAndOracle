// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/INFTMarket_V5_1.sol";

interface ITokenBank {
    function tokensReceived(address, address, uint256) external returns (bool);
}

/**
 * @title The ERC-20 token contract which also realize the functionalities of ERC777 and ERC20-permit(ERC2612)
 *
 * @author Garen Woo
 */
contract GTST is ERC20, ERC20Permit, ReentrancyGuard {
    using SafeERC20 for GTST;
    using Address for address;

    address public owner;

    error NotOwner(address caller);
    error NoTokenReceived();
    error transferTokenFail();
    error NotContract();

    event TokenMinted(address recipient, uint256 amount, uint256 timestamp);
    event TransferedWithCallback(address target, uint256 amount);
    event TransferedWithCallbackForNFT(address target, uint256 amount, bytes data);

    constructor() ERC20("Garen Test Safe Token", "GTST") ERC20Permit("Garen Test Safe Token") {
        owner = msg.sender;
        /// @dev Initial totalsupply is 100,000
        _mint(msg.sender, 100000 * (10 ** uint256(decimals())));
    }

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert NotOwner(msg.sender);
        }
        _;
    }

    function mint(address _recipient, uint256 _amount) external onlyOwner {
        _mint(_recipient, _amount);
        emit TokenMinted(_recipient, _amount, block.timestamp);
    }

    /**
     * @notice This is the callback function realization of ERC777 which allows `_to` to handle the ERC-20 token of `address(this)`
     * 
     * @dev The approval of the ERC-20 token of `address(this)` should be conducted separately by the token owner.
     * This is for the consideration of the security of the callback pattern which may realize malicious logic in the target contract.
     */
    function transferWithCallback(address _to, uint256 _amount) external nonReentrant returns (bool) {
        bool transferSuccess = transfer(_to, _amount);
        if (!transferSuccess) {
            revert transferTokenFail();
        }
        if (_isContract(_to)) {
            bool success = ITokenBank(_to).tokensReceived(address(this), msg.sender, _amount);
            if (!success) {
                revert NoTokenReceived();
            }
        }
        emit TransferedWithCallback(_to, _amount);
        return true;
    }

    /** 
     * @notice ERC721 token callback function
     * Once an amount of ERC-20 token of `address(this)` is transferred to the NFTMarket, the action of buying NFT will be conducted.
     *
     * @dev The approval of the ERC-20 token of `address(this)` should be conducted separately by the token owner.
     * This is for the consideration of the security of the callback pattern which may realize malicious logic in the target contract.
     *
     * @param _data contains information of NFT, including ERC721Token address and tokenId.
     */
    function transferWithCallbackForNFT(address _to, uint256 _bidAmount, bytes calldata _data)
        external
        nonReentrant
        returns (bool)
    {
        if (_isContract(_to)) {
            INFTMarket_V5_1(_to).tokensReceived(msg.sender, address(this), _bidAmount, _data);
        } else {
            revert NotContract();
        }
        emit TransferedWithCallbackForNFT(_to, _bidAmount, _data);
        return true;
    }

    function getBytesOfNFTInfo(address _NFTAddr, uint256 _tokenId) public pure returns (bytes memory) {
        bytes memory NFTInfo = abi.encode(_NFTAddr, _tokenId);
        return NFTInfo;
    }

    function getOwner() public view returns (address) {
        return owner;
    }
    function _isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }
}
