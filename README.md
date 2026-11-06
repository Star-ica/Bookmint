# BookMint
Contracts (`contracts/`), Hardhat tests (`test/`), single-file frontend (`frontend/index.html`), whitepaper (`BookMint_Whitepaper.pdf`).

## Test
    npm install && npx hardhat test

## Deploy
1. `export RPC_URL=<testnet rpc> PK=<deployer key>` (never commit keys).
2. With real tokens: `BOT=0x.. USDT=0x.. npx hardhat run scripts/deploy.js --network sepolia`.
   Without: omit BOT/USDT and mock tokens are deployed (testnets only; `mint()` is open).
3. Paste the printed addresses into `CFG` at the top of the script in `frontend/index.html`. Set `CFG.DECIMALS` to the token's decimals (USDT is often 6; both tokens must share it in this version).
4. Serve statically (`npx serve frontend`) and open with MetaMask on the same network.

## Limitations
Ebook files/covers are NOT stored onchain; `contentRef`/`coverRef` are external, publicly readable strings. No DRM is enforced. Contracts are unaudited.
# Bookmint
