// SPDX-License-Identifier: MIT
pragma solidity =0.8.7;

import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

import "./utils/AccessProtected.sol";
import "./utils/BaseRelayRecipient.sol";
import "./ERC2981Royalties.sol";

contract ShowtimeMT is ERC1155Burnable, ERC2981Royalties, AccessProtected, BaseRelayRecipient {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    string public baseURI = "https://gateway.pinata.cloud/ipfs/";
    mapping(uint256 => string) private _hashes;

    bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;

    constructor() ERC1155("") {}

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155, IERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * Mint + Issue Token
     *
     * @param recipient - Token will be issued to recipient
     * @param amount - amount of tokens to mint
     * @param hash - IPFS hash
     * @param data - additional data
     * @param royaltyRecipient - royalty receiver address
     * @param royaltyPercent - percentage of royalty
     */
    function issueToken(
        address recipient,
        uint256 amount,
        string memory hash,
        bytes memory data,
        address royaltyRecipient,
        uint256 royaltyPercent
    ) public onlyMinter returns (uint256) {
        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();
        _hashes[newTokenId] = hash;
        _mint(recipient, newTokenId, amount, data);
        if (royaltyPercent > 0) {
            _setTokenRoyalty(newTokenId, royaltyRecipient, royaltyPercent);
        }
        return newTokenId;
    }

    /**
     * Mint + Issue Token Batch
     *
     * @param recipient - Token will be issued to recipient
     * @param amounts - amounts of each token to mint
     * @param hashes - IPFS hashes
     * @param data - additional data
     * @param royaltyRecipients - royalty receiver addresses
     * @param royaltyPercents - percentages of royalty
     */
    function issueTokenBatch(
        address recipient,
        uint256[] memory amounts,
        string[] memory hashes,
        bytes memory data,
        address[] memory royaltyRecipients,
        uint256[] memory royaltyPercents
    ) public onlyMinter returns (uint256[] memory) {
        require(
            amounts.length == hashes.length &&
                royaltyRecipients.length == royaltyPercents.length &&
                amounts.length == royaltyRecipients.length,
            "array length mismatch"
        );
        uint256[] memory ids = new uint256[](amounts.length);
        for (uint256 i = 0; i < amounts.length; i++) {
            _tokenIds.increment();
            uint256 newTokenId = _tokenIds.current();
            _hashes[newTokenId] = hashes[i];
            ids[i] = newTokenId;
            if (royaltyPercents[i] > 0) {
                _setTokenRoyalty(newTokenId, royaltyRecipients[i], royaltyPercents[i]);
            }
        }
        _mintBatch(recipient, ids, amounts, data);
        return ids;
    }

    /**
     * Set Base URI
     *
     * @param _baseURI - Base URI
     */
    function setBaseURI(string calldata _baseURI) external onlyOwner {
        baseURI = _baseURI;
    }

    /**
     * Get Token URI
     *
     * @param tokenId - Token ID
     */
    function uri(uint256 tokenId) public view override returns (string memory) {
        return string(abi.encodePacked(baseURI, _hashes[tokenId]));
    }

    /**
     * Set Trusted Forwarder
     *
     * @param _trustedForwarder - Trusted Forwarder address
     */
    function setTrustedForwarder(address _trustedForwarder) external onlyAdmin {
        trustedForwarder = _trustedForwarder;
    }

    /**
     * returns the message sender
     */
    function _msgSender() internal view override(Context, BaseRelayRecipient) returns (address) {
        return BaseRelayRecipient._msgSender();
    }
}
