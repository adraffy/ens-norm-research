# ens-emoji

Compress 3406 emoji sequences (11K codepoints, 40KB raw) into 359 storage slots (11KB payload) state machine to enable the following API:

```solidity
function read(uint24[] memory cps, uint256 pos) view returns (uint256 len) {
	// returns number of codepoints necessary 
	// to consume a valid emoji codepoint
	// according to ENS normalization rules
}
```

## /encoder/

1. Acquire `ens-normalize-hr.json` from [@adraffy/ens-normalize.js](https://github.com/adraffy/ens-normalize.js)
1. Run `compress.js` to build rules
1. Run `check.js` to validate rules
1. Run `payload.js` to create compressed payload 
1. Deploy `EmojiParser.sol`
1. Call `upload()` with data in `payload-chunks.json`