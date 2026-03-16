# Spearbit Automated Audit Questionnaire

### GitHub Repository Link (if private do share access to 0xmorph on Github)

https://github.com/aragon/ve-governance/tree/

### Which specific branch or commit hash should the scan be run on?

audit/spearbit-ai

### Is there a list of files or specific directories where the scan should be focused on? (Specified scope)

```
Clock_v1_2_0.sol
IClock_v1_2_0.sol
LinearIncreasingCurve.sol
IEscrowCurveIncreasing_v1_2_0.sol
DelegationHelper.sol
EscrowIVotesAdapter.sol
IEscrowIVotesAdapter.sol
VotingEscrowIncreasing_v1_2_0.sol
IVotingEscrowIncreasing_v1_2_0.sol
GaugesDaoFactory_v1_4_0.sol
CurveConstantLib.sol
CurveConstantLibFlat.sol
ProxyLib.sol
SignedFixedPointMathLib.sol
Lock_v1_2_0.sol
ILock.sol
IERC721EMB.sol
DynamicExitQueue.sol
IDynamicExitQueue.sol
GaugeVoterSetup_v1_4_0.sol
AddressGaugeVoter.sol
IAddressGaugeVoter.sol
```

### Describe the documentation available for the codebase (e.g., links to architecture overview, specific function descriptions, threat models, etc.)

> This will greatly improve performance of the scan as assumptions of the protocol behavior can be properly documented/reviewed against

The contracts of interest are detailed inside the relevant specification documents, sitting inside [src/spec](./src/spec/).

### What specific types of bugs or vulnerabilities are you expecting or hoping the AI scan will find?

It would be great to understand if the 'constant' VE that is requested by a number of our clients (linear coefficient 0, quadratic 0, max epochs 0), causes any major issues. We have tested this extensively but an extra layer of security would be very much appreciated.

### What is your expected deadline for receiving the final security report?

20/2/26

### On a scale of 1 to 5, how critical is the urgency of this scan?

3
