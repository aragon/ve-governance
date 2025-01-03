# Risc Zero Total Supply

## Links

- [Discussion w. Carlos](https://app.excalidraw.com/s/59mdtwjNJ4i/14rCvVnTXCp)
- [Discussion w. GPT](https://chatgpt.com/share/67740d5b-b878-8004-9d53-95adf3e99880)

This is a brief working document to explain the architecture approach that will yield onchain total supply using storage proofs.

## The Problem

We currently do not maintain any global state that tracks the total voting power inside the ve system. The primary reason for this is that current implementations (namely, checkpoint-based as seen in curve) are:

- Complicated
- Expensive
- Not often needed

Primarily it's done to avoid for-loop calculations in voting power on the EVM with gas limits and computational limits. If we offload the computation to a coprocessor, and then use storage proofs to guarantee the data, this can be a potential improvement on the existing system.

## Requirements of the storage proof solution

Key things are to ensure the right algorithm is run for evaluating voting power and that all data is included.

In the R0 architecture, the guest program is stored against an image ID which is stored onchain. We include the image ID in the proof (I think) so this is covered.

We then need to guarantee inclusion and exclusion:

1. Inclusion: nobody who has voting power is excluded
2. Exclusion: nobody who has no voting power is included

One way to achieve this is to write every TokenPoint to an array:

```solidity
/// @notice Captures the shape of the user's voting curve at a specific point in time
/// @param bias The y intercept of the user's voting curve at the given time
/// @param checkpointTs The checkpoint when the user voting curve is/was/will be updated
/// @param writtenTs The timestamp at which we locked the checkpoint
/// @param coefficients The coefficients of the curve, supports up to quadratic curves.
/// @dev Coefficients are stored in the following order: [constant, linear, quadratic]
/// and not all coefficients are used for all curves.
struct TokenPoint {
    uint256 bias;
    uint128 checkpointTs;
    uint128 writtenTs;
    int256[3] coefficients;
}


/// define this in our contract
TokenPoint[] public points;
```

The tokenPoint above takes up 5 storage slots, this can be further compressed to 3 if:

- Linear Curves are used (requiring 2 coefficients)
- We deprecate the bias in place of `coefficients[0]`, which is typically equivalent

Either way, if we stored the array, the requirement of the storage proof is to iterate over each element in the array.

By storing an enumerable array of all points, we can then design the guest application to ensure that a proof is provided that includes all poibnts.

## Implementation

Simple really: we just push to the points array during every checkpoint, but we need to also include the token point itself when pushing to the array.

This is tough to implement in a backwards-compatible manner though

## Backwards compatible option

Alternatively, the data we need is spread across the following points:

1. The tokenIds

`VotingEscrowIncreasing.lastLockId()` returns the latest tokenId created at a given block. So if on block 100, the last ID was 777, that means we have at most 777 veNFTs at block 100.

This gives us the inclusion data: we know we need to loop 777 times for a tokenId

2. The tokenPointIntervals

`QuadraticIncreasingEscrow.tokenPointIntervals(tokenId)` is the length of the array for a given tokenId. Put another way:

- If the token has a tokenPointInterval of 1 - there is only 1 point that must be included
- If the token has a tokenPointInterval of 2 - there are 2 points

In the case of tokenPointInterval == 0, there is no tokenPoint, but this should not happen as we only iterate over tokenIds that exist (lastLockId)

3. The data

The data is contained in `\_tokenPointHistory` which is internal and stored in slot 4 (0 indexed) of the escrow contract (after accounting for the inheritance chain). We can wrap a getter for this:

```solidity
function getTokenPointHistory(
  uint256 _tokenId
) external view returns (TokenPoint[] memory) {
  // check the interval
  uint256 ival = tokenPointIntervals[_tokenId];

  TokenPoint[] memory history = new TokenPoint[](ival);

  if (ival > 0) {
    for (uint256 i; i <= ival; i++) {
      history[i] = _tokenPointHistory[_tokenId][i];
    }
  }

  return history;
}
```

This is where my knowledge of Risc 0 and steel breaks down a bit.
