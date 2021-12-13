# marketplace-v1-public

## ShowtimeV1Market.sol

`ShowtimeV1Market` is the marketplace for Showtime NFTs. It will be deployed on Polygon mainnet.

Users can either interact with the contract directly or through meta-transactions using the `BiconomyForwarder` method described below.

Users can:

-   list a given amount of a token id for sale for a specific number of ERC20 tokens
-   cancel a listing
-   complete a sale (swap ERC20 tokens for the NFT listed for sale). If royalties are enabled, the corresponding portion of the ERC20 payment is transferred to the royalties recipient. Currently, we would expect this to be the creator of the NFT on Showtime.

Note: sales can be partial, e.g. if N tokens are for sale in a particular listing, the buyer can purchase M tokens where `M <= N`. The listing is then updated to reflect that there are now only `N - M` tokens left for sale.

The owner can:

-   pause the contract, which effectively prevents the completion of sales
-   add or remove ERC20 contract addresses that can be used to buy and sell NFTs
-   turn royalty payments on and off

Some limitations:

-   it is hardcoded to only support a single `ShowtimeMT` ERC1155 contract
-   it only supports transactions in a configurable list of ERC20 tokens, no native currency
-   it only supports buying and selling at a fixed price, no auctions
-   listings don't have an expiration date
-   if we ever migrate to another NFT contract (or add support for more NFT contracts), we will need to migrate to a new marketplace
-   the owner has no control over NFTs or any other balance owned by the `ShowtimeV1Market` contract

## Meta-transactions

Meta-transactions enable gas-less transactions (from the end user's point of view), for example:

-   a user wants to create an NFT
-   the app can prompt users to sign a message with the appropriate parameters
-   this message is sent to the Biconomy API
-   the `BiconomyForwarder` contract then interacts with `ShowtimeMT` / `ShowtimeV1Market` on behalf of the end user
-   `ShowtimeMT` / `ShowtimeV1Market` then rely on `BaseRelayRecipient._msgSender()` to get the address of the end user (`msg.sender` would return the address of the `BiconomyForwarder`)

⚠️ this method actually trusts `BiconomyForwarder` to send the correct address as the last bytes of `msg.data`, it can not verify
