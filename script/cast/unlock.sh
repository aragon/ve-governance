#!/bin/sh

# Load the signer address from the .env file and unlock it for use in test scripts via anvil
SIGNER=$(grep '^SIGNER_ADDRESS=' .env | cut -d '=' -f2)
echo "Unlocking $SIGNER"
cast rpc --rpc-url http://localhost:8545 anvil_impersonateAccount $SIGNER

ETH_WHALE="0xb4E38F1A3Bf250144364CF29076Ecd2D1f8C2329"
cast rpc --rpc-url http://localhost:8545 anvil_impersonateAccount $ETH_WHALE
cast send --from $ETH_WHALE --unlocked --value "10000000000000000000" $SIGNER --rpc-url http://localhost:8545
