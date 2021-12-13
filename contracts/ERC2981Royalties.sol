// SPDX-License-Identifier: MIT
pragma solidity =0.8.7;

import "@openzeppelin/contracts/interfaces/IERC2981.sol";

abstract contract ERC2981Royalties is IERC2981 {
    struct Royalty {
        address recipient;
        uint256 value; // as a % unit, from 0 - 10000 (2 extra 0s) for eg 25% is 2500
    }

    mapping(uint256 => Royalty) internal _royalties; // tokenId => royalty

    function _setTokenRoyalty(
        uint256 id,
        address recipient,
        uint256 value
    ) internal {
        require(value <= 100_00, "ERC2981Royalties: value too high");
        _royalties[id] = Royalty(recipient, value);
    }

    function royaltyInfo(uint256 _tokenId, uint256 _salePrice)
        external
        view
        override
        returns (address receiver, uint256 royaltyAmount)
    {
        Royalty memory royalty = _royalties[_tokenId];
        return (royalty.recipient, (_salePrice * royalty.value) / 100_00);
    }
}
