//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "./interfaces/IERC721Token_GOS_V3.sol";
import "./interfaces/INFTPermit.sol";

/**
 * @title This ERC721 token has permit checking that simulates a 'white list'. EOAs in the 'white list' can buy NFT from any NFT exchange
 *
 * @author Garen Woo
 */
contract ERC721Token_GOS_V3 is ERC721URIStorage, EIP712, IERC721Token_GOS_V3, INFTPermit, Nonces {
    address public owner;

    constructor() ERC721("Garen at OpenSpace", "GOS") EIP712("Garen at OpenSpace", "1") {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert NotOwner(msg.sender);
        }
        _;
    }

    function mint(address to, string memory tokenURI) public onlyOwner returns (uint256) {
        uint256 newItemId = nonces(address(this));
        _mint(to, newItemId);
        _setTokenURI(newItemId, tokenURI);
        _useNonce(address(this));
        return newItemId;
    }

    /**
     * @dev When 'buyer' buys a specific NFT(specified by input '_tokenId'), this function will check if 'buyer' is in "whitelist".
     * The splitted parts('_v', "_r", "_s") of the signed message, are checked for the validity of the signature.
     *
     * @param _spender the address which can control the NFT after the permit is verified to be valid
     * @param _tokenId the specific tokenId of the NFT which needs permit checking
     * @param _deadline the expire timestamp of the input signed message
     * @param _v ECDSA signature parameter v
     * @param _r ECDSA signature parameter r
     * @param _s ECDSA signature parameter s
     * @dev buyer is the EOA who wants to buy the NFT from the NFT exchange.
     */
    function NFTPermit_PrepareForBuy(
        address _spender,
        uint256 _tokenId,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external returns (bool) {
        address NFTAdmin = owner;
        address buyer = _spender;
        bytes32 PERMIT_TYPEHASH =
            keccak256("NFTPermit_PrepareForBuy(address buyer,uint256 tokenId,uint256 signerNonce,uint256 deadline)");
        if (block.timestamp > _deadline) {
            revert ExpiredSignature(block.timestamp, _deadline);
        }

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, buyer, _tokenId, _useNonce(NFTAdmin), _deadline));

        bytes32 hash = _hashTypedDataV4(structHash);

        address signer = ECDSA.recover(hash, _v, _r, _s);
        if (signer != NFTAdmin) {
            revert Unapproved(signer, NFTAdmin);
        }

        return true;
    }

    /**
     * @dev When a specific NFT(specified by input '_tokenId') is going to be listed by some EOA, this function will check if the owner is desired to list it.
     * Once the signature of message is successfully verified, the NFT will be approved to
     * The splitted parts('_v', "_r", "_s") of the signed message, are checked for the validity of the signature.
     *
     * @param _operator the address that is going to be approved to control the signer's all the NFTs. This should be a NFT Exchange contract.
     * @param _tokenId the specific tokenId of the NFT which needs permit checking
     * @param _price the price in token of the listed NFT
     * @param _deadline the expire timestamp of the input signed message
     * @param _v ECDSA signature parameter v
     * @param _r ECDSA signature parameter r
     * @param _s ECDSA signature parameter s
     *
     * @notice If the signed message is verified as valid, `_operatorApprovals[owner][operator]` will be set true in the NFT contract.
     * Unless User set it false by manually calling `setApprovalForAll` function in the NFT contract, it will keep true after the first call.
     */
    function NFTPermit_PrepareForList(
        address _operator,
        uint256 _tokenId,
        uint256 _price,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external returns (bool) {
        if (!_isContract(_operator)) {
            revert NotContract();
        }
        address NFTOwner = ownerOf(_tokenId);
        bytes32 PERMIT_TYPEHASH = keccak256(
            "NFTPermit_PrepareForList(address operator,uint256 tokenId,uint256 price,uint256 signerNonce,uint256 deadline)"
        );
        if (block.timestamp > _deadline) {
            revert ExpiredSignature(block.timestamp, _deadline);
        }

        bytes32 structHash =
            keccak256(abi.encode(PERMIT_TYPEHASH, _operator, _tokenId, _price, _useNonce(NFTOwner), _deadline));

        bytes32 hash = _hashTypedDataV4(structHash);

        address signer = ECDSA.recover(hash, _v, _r, _s);
        if (signer != NFTOwner) {
            revert Unapproved(signer, NFTOwner);
        }
        _setApprovalForAll(signer, _operator, true);
        return true;
    }

    /**
     * @notice This function compresses several parameters related to the NFT whitelist and finally returns the compressed data.
     * All the members in the whitelist can claim the NFT.
     *
     * @return whitelistData a compressed data of the whitelist of this NFT project, which should be provided to the member of this whitelist.
     */
    function generateWhitelistData(bytes32 _MerkleRoot) public view onlyOwner returns (bytes memory) {
        bytes memory whitelistData = abi.encode(address(this), _MerkleRoot);
        return whitelistData;
    }

    function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
        return
            _interfaceId == type(INFTPermit).interfaceId || super.supportsInterface(_interfaceId);
    }

    function _isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }
}
