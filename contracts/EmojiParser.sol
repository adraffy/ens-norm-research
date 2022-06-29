// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

contract EmojiParser {
 
	mapping (uint256 => uint256) emoji;

	function upload(bytes memory v) public {
		uint256 i;
		uint256 e;
		uint256 x;
		assembly {
			i := v
			e := sub(add(v, mload(v)), 1)
		}
		while (i < e) {
			assembly {
				i := add(i, 6) 
				x := mload(i) 
			}
			emoji[(x >> 16) & 0xFFFFFFFF] = x & 0xFFFF;
		}
	}

	function read(uint24[] memory cps, uint256 pos) public view returns (uint256 len) {
		uint256 state;
		uint256 eat;
		uint256 fe0f;
		uint256 extra;
		uint256 saved;
		while (pos < cps.length) {
			uint256 cp = cps[pos++]; 
			if (cp == 0xFE0F) {
				if (fe0f == 0) break;
				fe0f = 0;
				if (eat > 0) {
					len++;
				} else { 
					extra++;
				}
			} else {
				state = emoji[((state & 0xFF) << 24) | cp]; 
				if (state == 0) break;
				eat = (state & 0x1C00) >> 8;
				len += eat;
				if (extra > 0 && eat > 0) {
					len += extra;
					extra = 0;
				}
				fe0f = state >> 15;
				if ((state & 0x4000) != 0) {
					if (cp == saved) break;
				} else if ((state & 0x2000) != 0) {
					saved = cp;
				}
			}
		}
	}

}