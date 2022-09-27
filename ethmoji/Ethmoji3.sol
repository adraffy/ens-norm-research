/// @author raffy.eth
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

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

	// [pass]
	// 💩💩💩.eth
	// 🇺🇸🇺🇸.eth
	// 🇺🇸🇦🇴.eth
	// 👨‍👩‍👦.eth
	// 🧟‍♂.eth
	// 👨🏼‍❤‍💋‍👨🏽.eth
	// [fail]
	// 💩💩💩💩.eth
	// 🇦🇦🇦.eth
	// 👨‍👩‍👦👨‍👩‍👦.eth

	function test(string memory name) public view returns (string memory display, uint256 label_hash, bytes memory parsed, bytes32 node) {
		uint256 len = bytes(name).length;
		require(len >= 7, "too short"); // 3 + ".eth"
		uint256 suffix;
		assembly {
			suffix := mload(add(name, len))
		}
		require((suffix & 0xFFFFFFFF) == 0x2E657468, ".eth"); // require that it ends in .eth
		bytes memory temp;
		(temp, parsed) = beautify(bytes(name)); // throws if not normalized ethmoji		
		if (parsed.length == 4) { // single 	
			uint256 n = uint8(parsed[0]);
			uint256 num_cp = uint8(parsed[1]);
			if (num_cp == 1) {
				require(n == 3, "not 3 single");
			} else if (num_cp == 2) {
				require(n == 2, "not 2 double");
			} else {
				require(n == 1, "not 1 complex");
			}
			// truncate to 1
			n = uint8(parsed[3]);
			assembly {
				//mstore(temp, n)
			}
		} else if (parsed.length == 8) { // double
			require(uint8(parsed[0]) == 1 && uint8(parsed[1]) == 2, "not double 0");
			require(uint8(parsed[4]) == 1 && uint8(parsed[5]) == 2, "not double 1");
			// temp is [flag][flag]
		}
		display = string(temp);
		assembly {
			label_hash := keccak256(add(name, 32), sub(len, 4)) // compute label hash
		}
		node = keccak256(abi.encodePacked(uint256(0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae), label_hash));
	}

	function beautify(bytes memory name) private view returns (bytes memory beauty, bytes memory parsed) {
		unchecked {
			uint256 src_prev;
			uint256 src_next;
			uint256 src_end;
			uint256 dst_prev;
			uint256 dst_next;  
			uint256 hash_prev;
			uint256 parsed_end;
			uint256 cp_count;
			uint256 repeated;
			uint256 src_len = name.length - 4; // drop .eth
			parsed = new bytes(src_len << 2); // byte(count) + byte(ncp) + byte(step) 
			beauty = new bytes(src_len << 2); // we might add fe0f
			assembly {
				src_prev := name
				src_end := add(src_prev, src_len)
				dst_prev := beauty
			}
			while (src_prev < src_end) {
				(src_next, dst_next, cp_count) = processEmoji(src_prev, src_end, dst_prev);
				require(dst_next > dst_prev, "not emoji"); 
				uint256 src_step = src_next - src_prev;
				uint256 hash;
				assembly {
					hash := keccak256(add(src_prev, 32), src_step)
				}
				if (hash == hash_prev && repeated < 255) {
					repeated++;
				} else {
					if (repeated != 0) {
						parsed[parsed_end-4] = bytes1(uint8(repeated));
					}
					repeated = 1;
					hash_prev = hash;
					parsed[parsed_end+1] = bytes1(uint8(cp_count)); // number of codepoints
					parsed[parsed_end+2] = bytes1(uint8(src_step)); // bytes read
					parsed[parsed_end+3] = bytes1(uint8(dst_next - dst_prev)); // bytes written
					parsed_end += 4;
				}
				src_prev = src_next;
				dst_prev = dst_next;				
			}
			parsed[parsed_end-4] = bytes1(uint8(repeated)); // number of emoji
			assembly {
				mstore(beauty, sub(dst_prev, beauty))
				mstore(parsed, parsed_end)
			}
		}
	}

	function processEmoji(uint256 pos, uint256 end, uint256 dst0) private view returns (uint256 valid_pos, uint256 dst, uint256 cp_count) {
		unchecked {
			uint256 state;
			uint256 saved;
			uint256 buf; // the largest emoji is 35 bytes, which exceeds 32-byte buf
			uint256 len; // but the largest non-valid emoji sequence is only 27-bytes
			uint256 state0;
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
				cp_count++;
				pos += step; 
				len += step; 
				buf = (buf << (step << 3)) | raw; // use raw instead of converting cp back to UTF8
				if ((state & EMOJI_STATE_FE0F) != 0) {
					buf = (buf << 24) | 0xEFB88F; // UTF8-encoded FE0F
					len += 3;		
				}
				if ((state & EMOJI_STATE_VALID) != 0) { // valid
					state0 = state;
					dst = appendBytes(dst, buf, len);
					buf = 0;
					len = 0;
					valid_pos = pos; // everything output so far is valid
				} 
			}
			if ((state0 & EMOJI_STATE_QUIRK) != 0) {
				// the first FE0F is wrong
				// have: A FE0F B C D 
				// want: A B C D
				// where FE0F is 3 bytes (see above)
				(, uint256 quirk, ) = readUTF8(dst0); // length of first codepoint
				quirk += dst0; // offset of first codepoint
				while (quirk < dst) { // move left 3 bytes
					assembly {
						quirk := add(quirk, 32)
						mstore(quirk, mload(add(quirk, 3))) 
					}
				}
				dst -= 3;
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