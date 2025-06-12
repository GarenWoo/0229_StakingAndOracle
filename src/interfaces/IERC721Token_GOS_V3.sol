//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title An interface for The NFT named "GOS", which has realized some unique functions.
 *
 * @author Garen Woo
 */
interface IERC721Token_GOS_V3 {
    /**
     * @dev Indicates a failure when `msg.sender` is not the owner of the NFT contract.
     */
    error NotOwner(address caller);

    /**
     * @dev Indicates a failure when the signer of the signed message is not the expected address.
     */
    error Unapproved(address derivedSigner, address validSigner);

    /**
     * @dev Indicates a failure when the validating signature is expired.
     */
    error ExpiredSignature(uint256 currendTimestamp, uint256 deadline);

    /**
     * @dev Indicates a failure when the operator of a NFT is not a contract.
     */
    error NotContract();

    function mint(address to, string memory tokenURI) external returns (uint256);

    /**
     * @notice This function compresses several parameters related to the NFT whitelist and finally returns the compressed data.
     * All the members in the whitelist can claim the NFT.
     *
     * @return whitelistData a compressed data of the whitelist of this NFT project, which should be provided to the member of this whitelist.
     */
    function generateWhitelistData(bytes32 _MerkleRoot) external view returns (bytes memory);
}
