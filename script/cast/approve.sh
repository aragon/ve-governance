#!/bin/sh
ETH_WHALE="0xE28842dAF2cDe94EecC81b26A436eB043454F010"
MULTISIG="0x4315B4D2C707981f7fA51DBE91079Ea8c44e2e95"
RPC_FLAG="--rpc-url http://localhost:8545"
PROPOSAL_ID=2

SIGNER_0="0x946138B088524414EEDaf0699BA10d7Fb5673A34"
SIGNER_1="0xbd3eE47A1576F26454C65B96b7AbfaF8Ee9cB4a1"
SIGNER_2="0x9395e6b95afFee7d7b2b107127Fcc9e4167A336f"

cast send $SIGNER_0 --from $ETH_WHALE --unlocked --value "0.01ether" $RPC_FLAG
cast send $SIGNER_1 --from $ETH_WHALE --unlocked --value "0.01ether" $RPC_FLAG
cast send $SIGNER_2 --from $ETH_WHALE --unlocked --value "0.01ether" $RPC_FLAG

cast send $MULTISIG --from $SIGNER_0 --unlocked "approve(uint256,bool)" $PROPOSAL_ID false $RPC_FLAG
cast send $MULTISIG --from $SIGNER_1 --unlocked "approve(uint256,bool)" $PROPOSAL_ID false $RPC_FLAG
cast send $MULTISIG --from $SIGNER_2 --unlocked "approve(uint256,bool)" $PROPOSAL_ID true $RPC_FLAG
