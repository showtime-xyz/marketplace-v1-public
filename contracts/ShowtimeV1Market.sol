// SPDX-License-Identifier: MIT
pragma solidity =0.8.7;

import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Ownable, Context } from "@openzeppelin/contracts/access/Ownable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { BaseRelayRecipient } from "./utils/BaseRelayRecipient.sol";
import { ShowtimeMT } from "./ShowtimeMT.sol";

/// @title Showtime V1 Market for the Showtime ERC1155 Token
///
/// This is a non-escrow marketplace that allows users to list Showtime NFTs for sale
/// for a fixed price, using a configurable list of allowed ERC20 currencies.
///
/// @dev listings have no expiration date, but frontends may choose to hide old listings
///
/// Built with feedback from the community! ♥️
/// Big thanks to:
///     aaronsebesta chejazi chiuzon garythung mariobyn_eth MarkBeylin sina_eth_
///     StErMi theramblingboy timidan_x transmissions11 William94029369
contract ShowtimeV1Market is Ownable, Pausable, BaseRelayRecipient {
    using SafeERC20 for IERC20;
    using Address for address;

    /// the address of the ShowtimeMT NFT (ERC1155) contract
    ShowtimeMT public immutable nft;

    /// @dev listings only contain a tokenId because we are implicitly only listing tokens from the ShowtimeMT contract
    struct Listing {
        uint256 tokenId;
        uint256 quantity;
        uint256 price;
        IERC20 currency;
        address seller;
    }

    /// ============ Mutable storage ============

    /// royalties payments can be turned on/off by the owner of the contract
    bool public royaltiesEnabled = true;

    /// the configurable cap on royalties, enforced during the sale (50% by default)
    uint256 public maxRoyaltiesBasisPoints = 50_00;

    /// the configurable list of accepted ERC20 contract addresses
    mapping(address => bool) public acceptedCurrencies;

    /// maps a listing id to the corresponding Listing
    mapping(uint256 => Listing) public listings;

    /// a simple counter to assign ids to new listings
    uint256 listingCounter;

    /// ============ Modifiers ============

    modifier onlySeller(uint256 _id) {
        require(listings[_id].seller == _msgSender(), "caller not seller");
        _;
    }

    modifier listingExists(uint256 _id) {
        require(listings[_id].seller != address(0), "listing doesn't exist");
        _;
    }

    /// ============ Events ============

    /// marketplace and listing related events
    event ListingCreated(uint256 indexed listingId, address indexed seller, uint256 indexed tokenId);
    event ListingDeleted(uint256 indexed listingId, address indexed seller);
    event RoyaltyPaid(address indexed receiver, IERC20 currency, uint256 amount);
    event SaleCompleted(
        uint256 indexed listingId,
        address indexed seller,
        address indexed buyer,
        address receiver,
        uint256 quantity
    );

    /// admin events
    event AcceptedCurrencyChanged(address indexed account, address currency, bool accepted);
    event RoyaltiesEnabledChanged(address indexed account, bool royaltiesEnabled);
    event MaxRoyaltiesUpdated(address indexed account, uint256 maxRoyaltiesBasisPoints);

    /// ============ Constructor ============

    constructor(
        address _nft,
        address _trustedForwarder,
        address[] memory _initialCurrencies
    ) {
        /// initialize the address of the NFT contract
        require(_nft.isContract(), "must be contract address");
        nft = ShowtimeMT(_nft);

        for (uint256 i = 0; i < _initialCurrencies.length; i++) {
            require(_initialCurrencies[i].isContract(), "_initialCurrencies must contain contract addresses");
            acceptedCurrencies[_initialCurrencies[i]] = true;
        }

        /// set the trustedForwarder only once, see BaseRelayRecipient
        trustedForwarder = _trustedForwarder;
    }

    /// ============ Marketplace functions ============

    /// @notice `setApprovalForAll` before calling
    /// @notice creates a new Listing
    /// @param _quantity the number of tokens to be listed
    /// @param _price the price per token
    function createSale(
        uint256 _tokenId,
        uint256 _quantity,
        uint256 _price,
        address _currency
    ) external whenNotPaused returns (uint256 listingId) {
        address seller = _msgSender();

        require(acceptedCurrencies[_currency], "currency not accepted");
        require(_quantity > 0, "quantity must be greater than 0");
        require(nft.balanceOf(seller, _tokenId) >= _quantity, "seller does not own listed quantity of tokens");

        Listing memory listing = Listing({
            tokenId: _tokenId,
            quantity: _quantity,
            price: _price,
            currency: IERC20(_currency),
            seller: seller
        });

        listingId = listingCounter;
        listings[listingId] = listing;

        // no need to check for overflows here
        unchecked {
            listingCounter++;
        }

        emit ListingCreated(listingId, seller, _tokenId);
    }

    /// @notice cancel an active sale
    function cancelSale(uint256 _listingId) external listingExists(_listingId) onlySeller(_listingId) {
        delete listings[_listingId];

        emit ListingDeleted(_listingId, _msgSender());
    }

    /// @notice the seller may own fewer NFTs than the listed quantity
    function availableForSale(uint256 _listingId) public view listingExists(_listingId) returns (uint256) {
        Listing memory listing = listings[_listingId];
        return Math.min(nft.balanceOf(listing.seller, listing.tokenId), listing.quantity);
    }

    /// @notice Complete a sale
    /// @param _quantity the number of tokens to purchase
    /// @param _receiver the address that will receive the NFTs
    /// @dev we let the transaction complete even if the currency is no longer accepted in order to avoid stuck listings
    function buy(
        uint256 _listingId,
        uint256 _tokenId,
        uint256 _quantity,
        uint256 _price,
        address _currency,
        address _receiver
    ) external listingExists(_listingId) whenNotPaused {
        /// 1. Checks
        require(_receiver != address(0), "_receiver cannot be address 0");

        Listing memory listing = listings[_listingId];

        // to prevent issues with block reorgs, we need to make sure that the expectations of the buyer (tokenId,
        // price and currency) match with the listing
        require(listing.tokenId == _tokenId, "_tokenId does not match listing");
        require(listing.price == _price, "_price does not match listing");
        require(address(listing.currency) == _currency, "_currency does not match listing");

        // disable buying something from the seller for the seller
        // note that the seller can still buy from themselves as a gift for someone else
        // the difference with a transfer is that this will result in royalties being paid out
        require(_receiver != listing.seller, "seller is not a valid receiver address");

        uint256 availableQuantity = availableForSale(_listingId);
        require(_quantity <= availableQuantity, "required more than available quantity");

        uint256 totalPrice = listing.price * _quantity;
        (address royaltyReceiver, uint256 royaltyAmount) = getRoyalties(listing.tokenId, totalPrice);
        require(royaltyAmount <= totalPrice, "royalty amount too big");

        /// 2. Effects
        updateListing(_listingId, availableQuantity - _quantity);

        emit SaleCompleted(_listingId, listing.seller, _msgSender(), _receiver, _quantity);

        /// 3. Interactions
        // transfer royalties
        if (royaltyAmount > 0) {
            emit RoyaltyPaid(royaltyReceiver, listing.currency, royaltyAmount);
            listing.currency.safeTransferFrom(_msgSender(), royaltyReceiver, royaltyAmount);
        }

        // the royalty amount is deducted from the price paid by the buyer
        listing.currency.safeTransferFrom(_msgSender(), listing.seller, totalPrice - royaltyAmount);

        // transfer the NFTs from the seller to the buyer
        nft.safeTransferFrom(listing.seller, _receiver, listing.tokenId, _quantity, "");
    }

    /// ============ Utility functions ============

    /// @notice update the listing with the remaining quantity, or delete it if newQuantity is zero
    function updateListing(uint256 listingId, uint256 newQuantity) private {
        if (newQuantity == 0) {
            address seller = listings[listingId].seller;
            delete listings[listingId];
            emit ListingDeleted(listingId, seller);
        } else {
            listings[listingId].quantity = newQuantity;
        }
    }

    function getRoyalties(uint256 tokenId, uint256 price)
        private
        view
        returns (address receiver, uint256 royaltyAmount)
    {
        if (!royaltiesEnabled) {
            return (address(0), 0);
        }

        (receiver, royaltyAmount) = nft.royaltyInfo(tokenId, price);

        // we ignore royalties to address 0, otherwise the transfer would fail
        // and it would result in NFTs that are impossible to sell
        if (receiver == address(0) || royaltyAmount == 0) {
            return (address(0), 0);
        }

        royaltyAmount = capRoyalties(price, royaltyAmount);
    }

    function capRoyalties(uint256 salePrice, uint256 royaltyAmount) private view returns (uint256) {
        uint256 maxRoyaltiesAmount = (salePrice * maxRoyaltiesBasisPoints) / 100_00;
        return Math.min(maxRoyaltiesAmount, royaltyAmount);
    }

    function _msgSender() internal view override(Context, BaseRelayRecipient) returns (address) {
        return BaseRelayRecipient._msgSender();
    }

    /// ============ Admin functions ============

    /// @notice switch royalty payments on/off
    function setRoyaltiesEnabled(bool newValue) external onlyOwner {
        royaltiesEnabled = newValue;

        emit RoyaltiesEnabledChanged(_msgSender(), royaltiesEnabled);
    }

    /// @notice sets the maximum royalties that will be paid during sales, in basis points
    /// ex: if a token requests 75% royalties but maxRoyaltiesBasisPoints is set to 60_00 (= 60%),
    ///    then 60% will be paid out instead of the 75% requested
    function setMaxRoyalties(uint256 newValue) external onlyOwner {
        require(newValue <= 100_00, "maxRoyaltiesBasisPoints must be <= 100%");
        maxRoyaltiesBasisPoints = newValue;

        emit MaxRoyaltiesUpdated(_msgSender(), maxRoyaltiesBasisPoints);
    }

    /// @notice add a currency to the accepted currency list
    function setAcceptedCurrency(address currency, bool accepted) external onlyOwner {
        require(currency.isContract(), "_currency != contract address");
        acceptedCurrencies[currency] = accepted;

        emit AcceptedCurrencyChanged(_msgSender(), currency, accepted);
    }

    /// @notice pause the contract
    function pause() external whenNotPaused onlyOwner {
        _pause();
    }

    /// @notice unpause the contract
    function unpause() external whenPaused onlyOwner {
        _unpause();
    }
}
