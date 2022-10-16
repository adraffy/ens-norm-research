/// @author raffy.eth
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Ownable} from "@openzeppelin/contracts@4.6.0/access/Ownable.sol";

contract Ethmoji is Ownable {

	uint256 constant EMOJI_STATE_MASK  = 0x07FF; 
	uint256 constant EMOJI_STATE_QUIRK = 0x0800;
	uint256 constant EMOJI_STATE_VALID = 0x1000;
	uint256 constant EMOJI_STATE_SAVE  = 0x2000;
	uint256 constant EMOJI_STATE_CHECK = 0x4000;
	uint256 constant EMOJI_STATE_FE0F  = 0x8000;

	mapping (uint256 => uint256) _emoji;

	function uploadEmoji(bytes calldata data) public onlyOwner {
		uint256 i;
		uint256 e;
		uint256 mask = 0xFFFFFFFF;
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
				k := and(calldataload(i), mask)
				i := add(i, 32)
			}
			_emoji[k] = v;
		}
	}

	function getEmoji(uint256 s0, uint256 cp) private view returns (uint256) {
		return (_emoji[(s0 << 20) | (cp >> 4)] >> ((cp & 0xF) << 4)) & 0xFFFF;
	}

	function test(string memory name) public view returns (string memory label, uint256 label_hash, bytes memory counts) {
		uint256 len = bytes(name).length;
		require(len >= 7, "too short"); // 3 + ".eth"
		uint256 suffix;
		assembly {
			suffix := mload(add(name, len))
		}
		require((suffix & 0xFFFFFFFF) == 0x2E657468, ".eth"); // require that it ends in .eth
		bytes memory temp;
	 	(temp, counts) = beautify(bytes(name)); // throws if not normalized ethmoji
		label = string(temp);
		// aaa = [3]
		// abc = [1,1,1]
		if (counts.length == 1) { // all emoji are the same
			uint256 n = uint8(counts[0]);
		}
		// if we got here, name is normalized		
		assembly {
			label_hash := keccak256(add(name, 32), sub(len, 4)) // compute label hash
		}
	}

	function beautify(bytes memory name) private view returns (bytes memory beaut, bytes memory counts) {
		unchecked {
			uint256 off;
			uint256 end;
			uint256 prev;
			uint256 next;  
			uint256 len = name.length - 4; // drop .eth
			beaut = new bytes(len << 2); // we might add fe0f
			counts = new bytes(len);
			assembly {
				off := name
				end := add(off, len)
				prev := beaut
			}
			uint256 hash0;
			uint256 count;
			while (off < end) {
				(off, next) = processEmoji(off, end, prev);
				require(next > prev, "not emoji"); 
				// compute hash of emoji
				uint256 hash;
				assembly {
					hash := keccak256(prev, sub(next, prev))
				}
				if (hash != hash0) { // different
					hash0 = hash;
					count++;
				}
				counts[count - 1] = bytes1(uint8(counts[count - 1]) + 1); // only counts up to 255
				//
				prev = next;		
			}
			assembly {
				mstore(beaut, sub(prev, beaut))
				mstore(counts, count)
			}
		}
	}

	function processEmoji(uint256 pos, uint256 end, uint256 dst0) private view returns (uint256 valid_pos, uint256 dst) {
		unchecked {
			uint256 state;
			uint256 saved;
			uint256 buf; // the largest emoji is 35 bytes, which exceeds 32-byte buf
			uint256 len; // but the largest non-valid emoji sequence is only 27-bytes
			dst = dst0;
			while (pos < end) {
				(uint256 cp, uint256 step, uint256 raw) = readUTF8(pos);
				state = getEmoji(state & EMOJI_STATE_MASK, cp);
				if (state == 0) break;
				if ((state & EMOJI_STATE_SAVE) != 0) { 
					saved = cp; 
				} else if ((state & EMOJI_STATE_CHECK) != 0) { 
					if (cp == saved) break;
				}
				pos += step; 
				len += step; 
				buf = (buf << (step << 3)) | raw; // use raw instead of converting cp back to UTF8
				if ((state & EMOJI_STATE_FE0F) != 0) {
					buf = (buf << 24) | 0xEFB88F; // UTF8-encoded FE0F
					len += 3;
				}
				if ((state & EMOJI_STATE_VALID) != 0) { // valid
					if ((state & EMOJI_STATE_QUIRK) != 0) {
						dst -= 3; // overwrite the last FE0F
					}
					dst = appendBytes(dst, buf, len);
					buf = 0;
					len = 0;
					valid_pos = pos; // everything output so far is valid
				} 
			}
		}
	}

	// read one cp from memory at ptr
	// step is number of encoded bytes (1-4)
	// raw is encoded bytes
	// warning: assumes valid UTF8
	function readUTF8(uint256 ptr) private pure returns (uint256 cp, uint256 step, uint256 raw) {
		// 0xxxxxxx => 1 :: 0aaaaaaa ???????? ???????? ???????? =>                   0aaaaaaa
		// 110xxxxx => 2 :: 110aaaaa 10bbbbbb ???????? ???????? =>          00000aaa aabbbbbb
		// 1110xxxx => 3 :: 1110aaaa 10bbbbbb 10cccccc ???????? => 000000aa aaaabbbb bbcccccc
		// 11110xxx => 4 :: 11110aaa 10bbbbbb 10cccccc 10dddddd => 000aaabb bbbbcccc ccdddddd
		assembly {
			raw := and(mload(add(ptr, 4)), 0xFFFFFFFF)
		}
		uint256 upper = raw >> 28;
		if (upper < 0x8) {
			step = 1;
			raw >>= 24;
			cp = raw;
		} else if (upper < 0xE) {
			step = 2;
			raw >>= 16;
			cp = ((raw & 0x1F00) >> 2) | (raw & 0x3F);
		} else if (upper < 0xF) {
			step = 3;
			raw >>= 8;
			cp = ((raw & 0x0F0000) >> 4) | ((raw & 0x3F00) >> 2) | (raw & 0x3F);
		} else {
			step = 4;
			cp = ((raw & 0x07000000) >> 6) | ((raw & 0x3F0000) >> 4) | ((raw & 0x3F00) >> 2) | (raw & 0x3F);
		}
	}

	// write len lower-bytes of buf at ptr
	// return ptr advanced by len
	function appendBytes(uint256 ptr, uint256 buf, uint256 len) private pure returns (uint256 ptr1) {
		assembly {
			ptr1 := add(ptr, len) // advance by len bytes
			let word := mload(ptr1) // load right-aligned word
			let mask := sub(shl(shl(3, len), 1), 1) // compute len-byte mask: 1 << (len << 3) - 1
			mstore(ptr1, or(and(word, not(mask)), and(buf, mask))) // merge and store
		}
	}


}