# Sample ERC4626 contract with Automated Underlying Strategy

This ERC4626 tokenized vault showcases some primitive financial tooling for building out automated yield generating strategies. ERC4626 is based of solmate implenetation. Includes uniswapv3 and aave v3 integrations.

Local hardhat fork of ETH mainnet is our deployment environmnet

```shell
npx hardhat node
npx hardhat run scripts/deploy_erc4626.js
```
