// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

contract EmojiParser {
 
	mapping (uint256 => uint256) emoji;

	function upload(bytes calldata data) public {
		uint256 i;
		uint256 e;
		assembly {
			i := data.offset
			e := add(i, data.length)
		}
		while (i < e) {
			uint256 k;
			uint256 v;
			assembly {
				v := calldataload(i)
				i := add(i, 4)
				k := and(calldataload(i), 0xFFFFFFFF)
				i := add(i, 32)
			}
			emoji[k] = v;
		}
	}

	function get_debug(uint256 state0, uint256 cp) public view returns (uint256 state1, uint256 eat, bool fe0f, bool save, bool check) {
		uint256 value = get(state0, cp);
		state1 = value & 0xFF;
		eat    = (value & 0x1E00) >> 9;
		fe0f   = (value & 0x8000) != 0;
		save   = (value & 0x4000) != 0;
		check  = (value & 0x2000) != 0;
	}

	function get(uint256 state0, uint256 cp) public view returns (uint256 value) {
		value = (emoji[((state0 & 0xFF) << 20) | (cp >> 4)] >> ((cp & 0xF) << 4)) & 0xFFFF;
	}

	function read(uint24[] memory cps, uint256 pos) public view returns (uint256 len) {
		uint256 state;
		uint256 eat;
		uint256 fe0f;
		uint256 extra;
		uint256 saved;
		unchecked { while (pos < cps.length) {
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
				state = get(state, cp);
				if (state == 0) break;
				eat = (state & 0x1E00) >> 9;
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
		} }
	}

	function filter(string memory s) public view returns (uint24[] memory cps) {
		cps = decodeUTF8(bytes(s));
		uint256 pos;
		uint256 out;
		while (pos < cps.length) {
			uint24 cp = cps[pos];
			if (cp == 0xFE0F) { // ignored
				pos++;
				continue;
			}
			uint256 len = read(cps, pos);
			if (len > 0) { // emoji
				cps[out++] = 0xFFFFFF;
				pos += len;
			} else { // non-emoji
				cps[out++] = cp;
				pos++;
			}
		}
		assembly { 
			mstore(cps, out) 
		}
	}

	function decode(string memory s) public pure returns (uint24[] memory cps) {
		cps = decodeUTF8(bytes(s));
	}

	error InvalidUTF8();

	function decodeUTF8(bytes memory v) private pure returns (uint24[] memory cps) {
		uint256 n = v.length;
		cps = new uint24[](n);
		uint256 i;
		uint256 j;
		unchecked { while (i < n) {
			uint256 cp = uint8(v[i++]);
			if ((cp & 0x80) == 0) { // [1] 0xxxxxxx
				//
			} else if ((cp & 0xE0) == 0xC0) { // [2] 110xxxxx (5)
				if (i >= n) revert InvalidUTF8();
				uint256 a = uint8(v[i++]);
				if ((a & 0xC0) != 0x80) revert InvalidUTF8();
				cp = ((cp & 0x1F) << 6) | a;
				if (cp < 0x80) revert InvalidUTF8();
			} else if ((cp & 0xF0) == 0xE0) { // [3] 1110xxxx (4)
				if (i + 2 > n) revert InvalidUTF8();
				uint256 a = uint8(v[i++]);
				uint256 b = uint8(v[i++]);
				if (((a | b) & 0xC0) != 0x80) revert InvalidUTF8();
				cp = ((cp & 0xF) << 12) | ((a & 0x3F) << 6) | (b & 0x3F);
				if (cp < 0x0800) revert InvalidUTF8();
			} else if ((cp & 0xF8) == 0xF0) { // [4] 11110xxx (3)
				if (i + 3 > n) revert InvalidUTF8();
				uint256 a = uint8(v[i++]);
				uint256 b = uint8(v[i++]);
				uint256 c = uint8(v[i++]);
				if (((a | b | c) & 0xC0) != 0x80) revert InvalidUTF8();
				cp = ((cp & 0x7) << 18) | ((a & 0x3F) << 12) | ((b & 0x3F) << 6) | (c & 0x3F);
				if (cp < 0x10000 || cp > 0x10FFFF) revert InvalidUTF8();
			} else {
				revert InvalidUTF8();
			}
			cps[j++] = uint24(cp);
		} }
		assembly { 
			mstore(cps, j) 
		}
	}

}