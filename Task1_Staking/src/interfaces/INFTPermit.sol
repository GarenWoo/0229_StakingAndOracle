//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title An interface of validation of signature for NFT. 
 * The ERC2612-like functionality is open to be utilized in the NFT contract which inherits this interface. 
 * It allows the validation of signed messages.
 *
 * @author Garen Woo
 */
interface INFTPermit {
    /**
     * @dev When 'buyer' buys a specific NFT(specified by input '_tokenId'), this function will check if 'buyer' is in "white-list".
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
    ) external returns (bool);

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
    ) external returns (bool);
}
