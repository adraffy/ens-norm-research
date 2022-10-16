// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import {Ownable} from "@openzeppelin/contracts@4.6.0/access/Ownable.sol";

contract Normalize is Ownable {

	// where key   = [9 bits: state0][20 bits: codepoint >> 4]
	// where value = 16x[2 byte: state]
	// where index = <lower 4 bits> of codepoint
	// where state = [3 bits: FE0F, Check Save][4: bits: eat][9 bits: state1]
	mapping (uint256 => uint256) _emoji;

	// where key   = [codepoint >> 8]
	// where value = 256x[1 bit: valid]
	// where index = <lower 8 bits> of codepoint
	mapping (uint256 => uint256) _valid;

	// mapping for cp => 1-2 cp
	// where key   = [codepoint >> 2]
	// where value = 4x[8 byte: 2x[3 byte: cp]]
	// where index = <lower 2 bits> of cp
	mapping (uint256 => uint256) _small; 

	// mapping for cp => 3-6 cp
	// where key   = [codepoint >> 1]
	// where value = 2x[16 byte: [2 bits: len] ... cps]
	// where index = <lower 1 bit> of cp
	// where len = 3 + [0-3] => 3-6 
	// where cps = len x [21 bits: cp], stored in reverse	
	mapping (uint256 => uint256) _large;

    function updateMapping(mapping (uint256 => uint256) storage map, bytes calldata data, uint256 keyBytes) private {
        uint256 i;
		uint256 e;
        uint256 keyMask = (1 << (keyBytes << 3)) - 1;
		assembly {
			i := data.offset
			e := add(i, data.length)
		}
		while (i < e) {
			uint256 k;
			uint256 v;
			assembly {
				v := calldataload(i)
				i := add(i, keyBytes)
				k := and(calldataload(i), keyMask)
				i := add(i, 32)
			}
			map[k] = v;
		}
    }


	function uploadEmoji(bytes calldata data) public onlyOwner {
		updateMapping(_emoji, data, 4);
	}
	function updateValid(bytes calldata data) public onlyOwner {
		updateMapping(_valid, data, 2);
	}
	function updateSmall(bytes calldata data) public onlyOwner {
		updateMapping(_small, data, 3);
	}
	function updateLarge(bytes calldata data) public onlyOwner {
		updateMapping(_large, data, 3);
	}


	function readEmoji(uint24[] memory cps, uint256 pos) public view returns (uint256 len) {
		uint256 state;
		uint256 eat;
		uint256 fe0f;
		uint256 extra;
		uint256 saved;
		unchecked { while (pos < cps.length) {
			uint256 cp = cps[pos++]; 
			if (cp == 0xFE0F) {
				if (fe0f == 0) break; // invalid FEOF
				fe0f = 0; // clear flag to prevent more
				if (eat > 0) {
					len++; // append immediately to output
				} else { 
					extra++; // combine into next output
				}
			} else {
				state = (_emoji[((state & 0xFF) << 20) | (cp >> 4)] >> ((cp & 0xF) << 4)) & 0xFFFF;
				if (state == 0) break;
				eat = (state & 0x1E00) >> 9; // codepoints to output (4 bits)
				len += eat; // non-zero if valid
				if (extra > 0 && eat > 0) { 
					len += extra; // include skipped FE0F
					extra = 0; // reset skipped
				}
				fe0f = state >> 15; // allow FEOF next?
				if ((state & 0x4000) != 0) { // check?
					if (cp == saved) break;
				} else if ((state & 0x2000) != 0) { // save?
					saved = cp; // save cp for later
				}
			}
		} }
	}

	function isIgnored(uint256 cp) public pure returns (bool) {
		if (cp < 0x2064) {
			return cp == 0xAD || cp == 0x200B || cp == 0x2060 || cp == 0x2064;
		} else if (cp < 0x1BCA0) {
			return cp == 0xFE0E || cp == 0xFE0F || cp == 0xFEFF;
		} else {
			return cp >= 0x1BCA0 && cp <= 0x1BCA3;
		}
	}


	error InvalidCodepoint(uint24 cp);
	
	//event Debug3(uint256 a, uint256 b, uint256 c);

	function normalize(string memory name) public view returns (string memory norm) {
		norm = encodeUTF8(normalizeRaw(name));
	}

	function normalizeRaw(string memory name) public view returns (uint24[] memory cps) {
		(uint24[] memory cps0, uint256 n) = decodeUTF8(name); // double capacity
		cps = new uint24[](bytes(name).length << 1); // guess
		uint256 pos;
		uint256 out;
		unchecked { while (pos < n) {
			uint256 temp = readEmoji(cps0, pos);
			if (temp > 0) { // emoji
				uint256 end = pos + temp;
				while (pos < end) {
					uint24 cp = cps0[pos++];
					if (cp != 0xFE0F) {
						cps[out++] = cp;
					}
				}
			} else {
				uint24 cp = cps0[pos++];
				if ((_valid[cp >> 8] & (1 << (cp & 0xFF))) != 0) {
					cps[out++] = cp;
				} else if (isIgnored(cp)) { 
					// ignored
				} else {
					temp = getMapped(cp);
					if (temp != 0) {
						cps[out++] = uint24(temp);
					} else {
						temp = (_small[cp >> 2] >> ((cp & 0x3) << 6)) & 0xFFFFFFFFFFFFFFFF;
						if (temp != 0) {
							if (temp < 0xFFFFFF) {
								cps[out++] = uint24(temp);
							} else {
								cps[out++] = uint24(temp >> 24);
								cps[out++] = uint24(temp);
							}
						} else {
							temp = (_large[cp >> 1] >> ((cp & 0x1) << 7)) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
							if (temp != 0) {
								uint256 end = out + 3 + (temp >> 126);
								if (end > cps.length) {
									uint24[] memory copy = new uint24[](end << 1);
									for (uint256 i; i < out; i++) {
										copy[i] = cps[i];
									}
									cps = copy;									
									/*
									uint256 slots = (out * 3 + 0x1F) >> 5; 
									//revert Overflow(cps.length, end, slots);
									uint256 src;
									assembly { src := cps } 
									cps = new uint24[](end << 1);
									uint256 dst;
									assembly { dst := cps }
									while (slots-- > 0) {
										assembly {
											src := add(src, 32)
											dst := add(dst, 32)
											mstore(dst, mload(src))
										}
									}
									*/
								}
								while (out < end) {
									cps[out++] = uint24(temp & 0x1FFFFF); 
									temp >>= 21;
								}
							} else {
								revert InvalidCodepoint(cp);
							}
						}
					}
				}
			}
		} }
		assembly { 
			mstore(cps, out) 
		}
	}

	function debugValid(uint256 cp) public view returns (bool) {
		return ((_valid[cp >> 8] & (1 << (cp & 0xFF))) != 0);
	}

	function debugSmall(uint256 cp) public view returns (uint256 value) {		
		value = (_small[cp >> 2] >> ((cp & 0x3) << 6)) & 0xFFFFFFFFFFFFFFFF;
	}

	function debugLarge(uint256 cp) public view returns (uint256 len, uint256 value) {		
		value = (_large[cp >> 1] >> ((cp & 0x1) << 7)) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
		len = 3 + (value >> 126);
		value &= 0x3FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
	}

	function debugDecode(string memory s) public pure returns (uint24[] memory cps) {
		uint256 len;
		(cps, len) = decodeUTF8(s);
		assembly {
			mstore(cps, len)
		}
	}

	// warning: unsafe if not utf8
	function decodeUTF8(string memory s) public pure returns (uint24[] memory cps, uint24 out) {
		bytes memory v = bytes(s);
		cps = new uint24[](v.length);
		uint256 i;
		unchecked { while (i < v.length) {
			uint256 cp = uint8(v[i++]);
			if (cp < 0x80) { // [1] 0xxxxxxx (7)
				//
			} else if ((cp & 0xE0) == 0xC0) { // [2] 110xxxxx (5)
				cp = ((cp & 0x1F) << 6) | (uint8(v[i++]) & 0x3F);
			} else if ((cp & 0xF0) == 0xE0) { // [3] 1110xxxx (4)
				uint256 a = uint8(v[i++]);
				uint256 b = uint8(v[i++]);
				cp = ((cp & 0x0F) << 12) | ((a & 0x3F) << 6) | (b & 0x3F);
			} else { // [4] 11110xxx (3)
				uint256 a = uint8(v[i++]);
				uint256 b = uint8(v[i++]);
				uint256 c = uint8(v[i++]);
				cp = ((cp & 0x07) << 18) | ((a & 0x3F) << 12) | ((b & 0x3F) << 6) | (c & 0x3F);
			}
			cps[out++] = uint24(cp);
		} }
	}

	function encodeUTF8(uint24[] memory cps) public pure returns (string memory s) {
		bytes memory v = new bytes(cps.length << 2); // guarenteed safe
		uint256 pos;
		uint256 ptr;
		uint256 buf;
		assembly {
			ptr := v
		}
		while (pos < cps.length) {
			uint256 cp = cps[pos++];
			if (cp < 0x80) {
				buf = (buf << 8) | cp;
				ptr++; 
			} else if (cp < 0x800) {
				buf = (buf << 16) | (0xC080 | (((cp << 2) & 0x1F00) | (cp & 0x003F)));
				ptr += 2;
			} else if (cp < 0x10000) {
				buf = (buf << 24) | (0xE08080 | (((cp << 4) & 0x0F0000) | ((cp << 2) & 0x003F00) | (cp & 0x00003F)));
				ptr += 3;
			} else {
				buf = (buf << 32) | (0xF0808080 | (((cp << 6) & 0x07000000) | ((cp << 4) & 0x003F0000) | ((cp << 2) & 0x00003F00) | (cp & 0x0000003F)));
				ptr += 4;
			}
			assembly {
				mstore(ptr, buf)
			}
		}
		assembly { 
			mstore(v, sub(ptr, v)) // truncate
		} 
		s = string(v);
	}


	function getMapped(uint256 cp) public pure returns (uint256 ret) {
		if (cp <= 0x556) {
			if (cp >= 0x41 && cp <= 0x5A) { // Mapped11: 26
				ret = cp + 0x20;
			} else if (cp >= 0x246 && cp < 0x250 && (cp & 1 == 0)) { // Mapped22: 5
				ret = cp + 1;
			} else if (cp >= 0x391 && cp <= 0x3A1) { // Mapped11: 17
				ret = cp + 0x20;
			} else if (cp >= 0x3A3 && cp <= 0x3A9) { // Mapped11: 7
				ret = cp + 0x20;
			} else if (cp >= 0x3D8 && cp < 0x3F0 && (cp & 1 == 0)) { // Mapped22: 12
				ret = cp + 1;
			} else if (cp >= 0x3FD && cp <= 0x3FF) { // Mapped11: 3
				ret = cp - 0x82;
			} else if (cp >= 0x404 && cp <= 0x406) { // Mapped11: 3
				ret = cp + 0x50;
			} else if (cp >= 0x408 && cp <= 0x40B) { // Mapped11: 4
				ret = cp + 0x50;
			} else if (cp >= 0x410 && cp <= 0x418) { // Mapped11: 9
				ret = cp + 0x20;
			} else if (cp >= 0x41A && cp <= 0x42F) { // Mapped11: 22
				ret = cp + 0x20;
			} else if (cp >= 0x460 && cp < 0x476 && (cp & 1 == 0)) { // Mapped22: 11
				ret = cp + 1;
			} else if (cp >= 0x478 && cp < 0x482 && (cp & 1 == 0)) { // Mapped22: 5
				ret = cp + 1;
			} else if (cp >= 0x48A && cp < 0x4C0 && (cp & 1 == 0)) { // Mapped22: 27
				ret = cp + 1;
			} else if (cp >= 0x4C3 && cp < 0x4CF && (cp & 1 == 0)) { // Mapped22: 6
				ret = cp + 1;
			} else if (cp >= 0x4FA && cp < 0x530 && (cp & 1 == 0)) { // Mapped22: 27
				ret = cp + 1;
			} else if (cp >= 0x531 && cp <= 0x556) { // Mapped11: 38
				ret = cp + 0x30;
			}
		} else if (cp <= 0x2138) {
			if (cp >= 0x13F8 && cp <= 0x13FD) { // Mapped11: 6
				ret = cp - 0x8;
			} else if (cp >= 0x1400 && cp <= 0x167F) { // Valid
				ret = cp;
			} else if (cp >= 0x1C90 && cp <= 0x1CBA) { // Mapped11: 43
				ret = cp - 0xBC0;
			} else if (cp >= 0x1CBD && cp <= 0x1CBF) { // Mapped11: 3
				ret = cp - 0xBC0;
			} else if (cp >= 0x1D33 && cp <= 0x1D3A) { // Mapped11: 8
				ret = cp - 0x1CCC;
			} else if (cp >= 0x1D5D && cp <= 0x1D5F) { // Mapped11: 3
				ret = cp - 0x19AB;
			} else if (cp >= 0x1DA4 && cp <= 0x1DA6) { // Mapped11: 3
				ret = cp - 0x1B3C;
			} else if (cp >= 0x1DAE && cp <= 0x1DB1) { // Mapped11: 4
				ret = cp - 0x1B3C;
			} else if (cp >= 0x1DBC && cp <= 0x1DBE) { // Mapped11: 3
				ret = cp - 0x1B2C;
			} else if (cp >= 0x1EFA && cp < 0x1F00 && (cp & 1 == 0)) { // Mapped22: 3
				ret = cp + 1;
			} else if (cp >= 0x2074 && cp <= 0x2079) { // Mapped11: 6
				ret = cp - 0x2040;
			} else if (cp >= 0x2080 && cp <= 0x2089) { // Mapped11: 10
				ret = cp - 0x2050;
			} else if (cp >= 0x2096 && cp <= 0x2099) { // Mapped11: 4
				ret = cp - 0x202B;
			} else if (cp >= 0x210B && cp <= 0x210E) { // Mapped10: 4
				ret = 0x68;
			} else if (cp >= 0x211B && cp <= 0x211D) { // Mapped10: 3
				ret = 0x72;
			} else if (cp >= 0x2135 && cp <= 0x2138) { // Mapped11: 4
				ret = cp - 0x1B65;
			}
		} else if (cp <= 0x326D) {
			if (cp >= 0x2460 && cp <= 0x2468) { // Mapped11: 9
				ret = cp - 0x242F;
			} else if (cp >= 0x24B6 && cp <= 0x24CF) { // Mapped11: 26
				ret = cp - 0x2455;
			} else if (cp >= 0x24D0 && cp <= 0x24E9) { // Mapped11: 26
				ret = cp - 0x246F;
			} else if (cp >= 0x27C0 && cp <= 0x2933) { // Valid
				ret = cp;
			} else if (cp >= 0x2C00 && cp <= 0x2C2F) { // Mapped11: 48
				ret = cp + 0x30;
			} else if (cp >= 0x2C67 && cp < 0x2C6D && (cp & 1 == 0)) { // Mapped22: 3
				ret = cp + 1;
			} else if (cp >= 0x2C80 && cp < 0x2CE4 && (cp & 1 == 0)) { // Mapped22: 50
				ret = cp + 1;
			} else if (cp >= 0x3137 && cp <= 0x3139) { // Mapped11: 3
				ret = cp - 0x2034;
			} else if (cp >= 0x313A && cp <= 0x313F) { // Mapped11: 6
				ret = cp - 0x1F8A;
			} else if (cp >= 0x3141 && cp <= 0x3143) { // Mapped11: 3
				ret = cp - 0x203B;
			} else if (cp >= 0x3145 && cp <= 0x314E) { // Mapped11: 10
				ret = cp - 0x203C;
			} else if (cp >= 0x314F && cp <= 0x3163) { // Mapped11: 21
				ret = cp - 0x1FEE;
			} else if (cp >= 0x3178 && cp <= 0x317C) { // Mapped11: 5
				ret = cp - 0x204D;
			} else if (cp >= 0x3184 && cp <= 0x3186) { // Mapped11: 3
				ret = cp - 0x202D;
			} else if (cp >= 0x3263 && cp <= 0x3265) { // Mapped11: 3
				ret = cp - 0x215E;
			} else if (cp >= 0x3269 && cp <= 0x326D) { // Mapped11: 5
				ret = cp - 0x215B;
			}
		} else if (cp <= 0xFB55) {
			if (cp >= 0x32E4 && cp <= 0x32E9) { // Mapped11: 6
				ret = cp - 0x21A;
			} else if (cp >= 0x32EE && cp <= 0x32F2) { // Mapped11: 5
				ret = cp - 0x210;
			} else if (cp >= 0x32F5 && cp <= 0x32FA) { // Mapped11: 6
				ret = cp - 0x20D;
			} else if (cp >= 0x32FB && cp <= 0x32FE) { // Mapped11: 4
				ret = cp - 0x20C;
			} else if (cp >= 0x3400 && cp <= 0xA48C) { // Valid
				ret = cp;
			} else if (cp >= 0xA4D0 && cp <= 0xA62B) { // Valid
				ret = cp;
			} else if (cp >= 0xA640 && cp < 0xA66E && (cp & 1 == 0)) { // Mapped22: 23
				ret = cp + 1;
			} else if (cp >= 0xA680 && cp < 0xA69C && (cp & 1 == 0)) { // Mapped22: 14
				ret = cp + 1;
			} else if (cp >= 0xA722 && cp < 0xA730 && (cp & 1 == 0)) { // Mapped22: 7
				ret = cp + 1;
			} else if (cp >= 0xA732 && cp < 0xA770 && (cp & 1 == 0)) { // Mapped22: 31
				ret = cp + 1;
			} else if (cp >= 0xA77E && cp < 0xA788 && (cp & 1 == 0)) { // Mapped22: 5
				ret = cp + 1;
			} else if (cp >= 0xA796 && cp < 0xA7AA && (cp & 1 == 0)) { // Mapped22: 10
				ret = cp + 1;
			} else if (cp >= 0xA7B4 && cp < 0xA7C4 && (cp & 1 == 0)) { // Mapped22: 8
				ret = cp + 1;
			} else if (cp >= 0xAB70 && cp <= 0xABBF) { // Mapped11: 80
				ret = cp - 0x97D0;
			} else if (cp >= 0xFB24 && cp <= 0xFB26) { // Mapped11: 3
				ret = cp - 0xF549;
			} else if (cp >= 0xFB52 && cp <= 0xFB55) { // Mapped10: 4
				ret = 0x67B;
			}
		} else if (cp <= 0xFBA3) {
			if (cp >= 0xFB56 && cp <= 0xFB59) { // Mapped10: 4
				ret = 0x67E;
			} else if (cp >= 0xFB5A && cp <= 0xFB5D) { // Mapped10: 4
				ret = 0x680;
			} else if (cp >= 0xFB5E && cp <= 0xFB61) { // Mapped10: 4
				ret = 0x67A;
			} else if (cp >= 0xFB62 && cp <= 0xFB65) { // Mapped10: 4
				ret = 0x67F;
			} else if (cp >= 0xFB66 && cp <= 0xFB69) { // Mapped10: 4
				ret = 0x679;
			} else if (cp >= 0xFB6A && cp <= 0xFB6D) { // Mapped10: 4
				ret = 0x6A4;
			} else if (cp >= 0xFB6E && cp <= 0xFB71) { // Mapped10: 4
				ret = 0x6A6;
			} else if (cp >= 0xFB72 && cp <= 0xFB75) { // Mapped10: 4
				ret = 0x684;
			} else if (cp >= 0xFB76 && cp <= 0xFB79) { // Mapped10: 4
				ret = 0x683;
			} else if (cp >= 0xFB7A && cp <= 0xFB7D) { // Mapped10: 4
				ret = 0x686;
			} else if (cp >= 0xFB7E && cp <= 0xFB81) { // Mapped10: 4
				ret = 0x687;
			} else if (cp >= 0xFB8E && cp <= 0xFB91) { // Mapped10: 4
				ret = 0x6A9;
			} else if (cp >= 0xFB92 && cp <= 0xFB95) { // Mapped10: 4
				ret = 0x6AF;
			} else if (cp >= 0xFB96 && cp <= 0xFB99) { // Mapped10: 4
				ret = 0x6B3;
			} else if (cp >= 0xFB9A && cp <= 0xFB9D) { // Mapped10: 4
				ret = 0x6B1;
			} else if (cp >= 0xFBA0 && cp <= 0xFBA3) { // Mapped10: 4
				ret = 0x6BB;
			}
		} else if (cp <= 0xFEC0) {
			if (cp >= 0xFBA6 && cp <= 0xFBA9) { // Mapped10: 4
				ret = 0x6C1;
			} else if (cp >= 0xFBAA && cp <= 0xFBAD) { // Mapped10: 4
				ret = 0x6BE;
			} else if (cp >= 0xFBD3 && cp <= 0xFBD6) { // Mapped10: 4
				ret = 0x6AD;
			} else if (cp >= 0xFBE4 && cp <= 0xFBE7) { // Mapped10: 4
				ret = 0x6D0;
			} else if (cp >= 0xFBFC && cp <= 0xFBFF) { // Mapped10: 4
				ret = 0x6CC;
			} else if (cp >= 0xFE41 && cp <= 0xFE44) { // Mapped11: 4
				ret = cp - 0xCE35;
			} else if (cp >= 0xFE8F && cp <= 0xFE92) { // Mapped10: 4
				ret = 0x628;
			} else if (cp >= 0xFE95 && cp <= 0xFE98) { // Mapped10: 4
				ret = 0x62A;
			} else if (cp >= 0xFE99 && cp <= 0xFE9C) { // Mapped10: 4
				ret = 0x62B;
			} else if (cp >= 0xFE9D && cp <= 0xFEA0) { // Mapped10: 4
				ret = 0x62C;
			} else if (cp >= 0xFEA1 && cp <= 0xFEA4) { // Mapped10: 4
				ret = 0x62D;
			} else if (cp >= 0xFEA5 && cp <= 0xFEA8) { // Mapped10: 4
				ret = 0x62E;
			} else if (cp >= 0xFEB1 && cp <= 0xFEB4) { // Mapped10: 4
				ret = 0x633;
			} else if (cp >= 0xFEB5 && cp <= 0xFEB8) { // Mapped10: 4
				ret = 0x634;
			} else if (cp >= 0xFEB9 && cp <= 0xFEBC) { // Mapped10: 4
				ret = 0x635;
			} else if (cp >= 0xFEBD && cp <= 0xFEC0) { // Mapped10: 4
				ret = 0x636;
			}
		} else if (cp <= 0xFF8A) {
			if (cp >= 0xFEC1 && cp <= 0xFEC4) { // Mapped10: 4
				ret = 0x637;
			} else if (cp >= 0xFEC5 && cp <= 0xFEC8) { // Mapped10: 4
				ret = 0x638;
			} else if (cp >= 0xFEC9 && cp <= 0xFECC) { // Mapped10: 4
				ret = 0x639;
			} else if (cp >= 0xFECD && cp <= 0xFED0) { // Mapped10: 4
				ret = 0x63A;
			} else if (cp >= 0xFED1 && cp <= 0xFED4) { // Mapped10: 4
				ret = 0x641;
			} else if (cp >= 0xFED5 && cp <= 0xFED8) { // Mapped10: 4
				ret = 0x642;
			} else if (cp >= 0xFED9 && cp <= 0xFEDC) { // Mapped10: 4
				ret = 0x643;
			} else if (cp >= 0xFEDD && cp <= 0xFEE0) { // Mapped10: 4
				ret = 0x644;
			} else if (cp >= 0xFEE1 && cp <= 0xFEE4) { // Mapped10: 4
				ret = 0x645;
			} else if (cp >= 0xFEE5 && cp <= 0xFEE8) { // Mapped10: 4
				ret = 0x646;
			} else if (cp >= 0xFEE9 && cp <= 0xFEEC) { // Mapped10: 4
				ret = 0x647;
			} else if (cp >= 0xFEF1 && cp <= 0xFEF4) { // Mapped10: 4
				ret = 0x64A;
			} else if (cp >= 0xFF10 && cp <= 0xFF19) { // Mapped11: 10
				ret = cp - 0xFEE0;
			} else if (cp >= 0xFF21 && cp <= 0xFF3A) { // Mapped11: 26
				ret = cp - 0xFEC0;
			} else if (cp >= 0xFF41 && cp <= 0xFF5A) { // Mapped11: 26
				ret = cp - 0xFEE0;
			} else if (cp >= 0xFF85 && cp <= 0xFF8A) { // Mapped11: 6
				ret = cp - 0xCEBB;
			}
		} else if (cp <= 0x10592) {
			if (cp >= 0xFF8F && cp <= 0xFF93) { // Mapped11: 5
				ret = cp - 0xCEB1;
			} else if (cp >= 0xFF96 && cp <= 0xFF9B) { // Mapped11: 6
				ret = cp - 0xCEAE;
			} else if (cp >= 0xFFA7 && cp <= 0xFFA9) { // Mapped11: 3
				ret = cp - 0xEEA4;
			} else if (cp >= 0xFFAA && cp <= 0xFFAF) { // Mapped11: 6
				ret = cp - 0xEDFA;
			} else if (cp >= 0xFFB1 && cp <= 0xFFB3) { // Mapped11: 3
				ret = cp - 0xEEAB;
			} else if (cp >= 0xFFB5 && cp <= 0xFFBE) { // Mapped11: 10
				ret = cp - 0xEEAC;
			} else if (cp >= 0xFFC2 && cp <= 0xFFC7) { // Mapped11: 6
				ret = cp - 0xEE61;
			} else if (cp >= 0xFFCA && cp <= 0xFFCF) { // Mapped11: 6
				ret = cp - 0xEE63;
			} else if (cp >= 0xFFD2 && cp <= 0xFFD7) { // Mapped11: 6
				ret = cp - 0xEE65;
			} else if (cp >= 0xFFDA && cp <= 0xFFDC) { // Mapped11: 3
				ret = cp - 0xEE67;
			} else if (cp >= 0xFFE9 && cp <= 0xFFEC) { // Mapped11: 4
				ret = cp - 0xDE59;
			} else if (cp >= 0x10400 && cp <= 0x10427) { // Mapped11: 40
				ret = cp + 0x28;
			} else if (cp >= 0x104B0 && cp <= 0x104D3) { // Mapped11: 36
				ret = cp + 0x28;
			} else if (cp >= 0x10570 && cp <= 0x1057A) { // Mapped11: 11
				ret = cp + 0x27;
			} else if (cp >= 0x1057C && cp <= 0x1058A) { // Mapped11: 15
				ret = cp + 0x27;
			} else if (cp >= 0x1058C && cp <= 0x10592) { // Mapped11: 7
				ret = cp + 0x27;
			}
		} else if (cp <= 0x1D44D) {
			if (cp >= 0x10600 && cp <= 0x10736) { // Valid
				ret = cp;
			} else if (cp >= 0x107B6 && cp <= 0x107B8) { // Mapped11: 3
				ret = cp - 0x105F6;
			} else if (cp >= 0x10C80 && cp <= 0x10CB2) { // Mapped11: 51
				ret = cp + 0x40;
			} else if (cp >= 0x118A0 && cp <= 0x118BF) { // Mapped11: 32
				ret = cp + 0x20;
			} else if (cp >= 0x11FFF && cp <= 0x12399) { // Valid
				ret = cp;
			} else if (cp >= 0x13000 && cp <= 0x1342E) { // Valid
				ret = cp;
			} else if (cp >= 0x14400 && cp <= 0x14646) { // Valid
				ret = cp;
			} else if (cp >= 0x16800 && cp <= 0x16A38) { // Valid
				ret = cp;
			} else if (cp >= 0x16E40 && cp <= 0x16E5F) { // Mapped11: 32
				ret = cp + 0x20;
			} else if (cp >= 0x17000 && cp <= 0x187F7) { // Valid
				ret = cp;
			} else if (cp >= 0x18800 && cp <= 0x18CD5) { // Valid
				ret = cp;
			} else if (cp >= 0x1B000 && cp <= 0x1B122) { // Valid
				ret = cp;
			} else if (cp >= 0x1B170 && cp <= 0x1B2FB) { // Valid
				ret = cp;
			} else if (cp >= 0x1D400 && cp <= 0x1D419) { // Mapped11: 26
				ret = cp - 0x1D39F;
			} else if (cp >= 0x1D41A && cp <= 0x1D433) { // Mapped11: 26
				ret = cp - 0x1D3B9;
			} else if (cp >= 0x1D434 && cp <= 0x1D44D) { // Mapped11: 26
				ret = cp - 0x1D3D3;
			}
		} else if (cp <= 0x1D53E) {
			if (cp >= 0x1D44E && cp <= 0x1D454) { // Mapped11: 7
				ret = cp - 0x1D3ED;
			} else if (cp >= 0x1D456 && cp <= 0x1D467) { // Mapped11: 18
				ret = cp - 0x1D3ED;
			} else if (cp >= 0x1D468 && cp <= 0x1D481) { // Mapped11: 26
				ret = cp - 0x1D407;
			} else if (cp >= 0x1D482 && cp <= 0x1D49B) { // Mapped11: 26
				ret = cp - 0x1D421;
			} else if (cp >= 0x1D4A9 && cp <= 0x1D4AC) { // Mapped11: 4
				ret = cp - 0x1D43B;
			} else if (cp >= 0x1D4AE && cp <= 0x1D4B5) { // Mapped11: 8
				ret = cp - 0x1D43B;
			} else if (cp >= 0x1D4B6 && cp <= 0x1D4B9) { // Mapped11: 4
				ret = cp - 0x1D455;
			} else if (cp >= 0x1D4BD && cp <= 0x1D4C3) { // Mapped11: 7
				ret = cp - 0x1D455;
			} else if (cp >= 0x1D4C5 && cp <= 0x1D4CF) { // Mapped11: 11
				ret = cp - 0x1D455;
			} else if (cp >= 0x1D4D0 && cp <= 0x1D4E9) { // Mapped11: 26
				ret = cp - 0x1D46F;
			} else if (cp >= 0x1D4EA && cp <= 0x1D503) { // Mapped11: 26
				ret = cp - 0x1D489;
			} else if (cp >= 0x1D507 && cp <= 0x1D50A) { // Mapped11: 4
				ret = cp - 0x1D4A3;
			} else if (cp >= 0x1D50D && cp <= 0x1D514) { // Mapped11: 8
				ret = cp - 0x1D4A3;
			} else if (cp >= 0x1D516 && cp <= 0x1D51C) { // Mapped11: 7
				ret = cp - 0x1D4A3;
			} else if (cp >= 0x1D51E && cp <= 0x1D537) { // Mapped11: 26
				ret = cp - 0x1D4BD;
			} else if (cp >= 0x1D53B && cp <= 0x1D53E) { // Mapped11: 4
				ret = cp - 0x1D4D7;
			}
		} else if (cp <= 0x1D6B8) {
			if (cp >= 0x1D540 && cp <= 0x1D544) { // Mapped11: 5
				ret = cp - 0x1D4D7;
			} else if (cp >= 0x1D54A && cp <= 0x1D550) { // Mapped11: 7
				ret = cp - 0x1D4D7;
			} else if (cp >= 0x1D552 && cp <= 0x1D56B) { // Mapped11: 26
				ret = cp - 0x1D4F1;
			} else if (cp >= 0x1D56C && cp <= 0x1D585) { // Mapped11: 26
				ret = cp - 0x1D50B;
			} else if (cp >= 0x1D586 && cp <= 0x1D59F) { // Mapped11: 26
				ret = cp - 0x1D525;
			} else if (cp >= 0x1D5A0 && cp <= 0x1D5B9) { // Mapped11: 26
				ret = cp - 0x1D53F;
			} else if (cp >= 0x1D5BA && cp <= 0x1D5D3) { // Mapped11: 26
				ret = cp - 0x1D559;
			} else if (cp >= 0x1D5D4 && cp <= 0x1D5ED) { // Mapped11: 26
				ret = cp - 0x1D573;
			} else if (cp >= 0x1D5EE && cp <= 0x1D607) { // Mapped11: 26
				ret = cp - 0x1D58D;
			} else if (cp >= 0x1D608 && cp <= 0x1D621) { // Mapped11: 26
				ret = cp - 0x1D5A7;
			} else if (cp >= 0x1D622 && cp <= 0x1D63B) { // Mapped11: 26
				ret = cp - 0x1D5C1;
			} else if (cp >= 0x1D63C && cp <= 0x1D655) { // Mapped11: 26
				ret = cp - 0x1D5DB;
			} else if (cp >= 0x1D656 && cp <= 0x1D66F) { // Mapped11: 26
				ret = cp - 0x1D5F5;
			} else if (cp >= 0x1D670 && cp <= 0x1D689) { // Mapped11: 26
				ret = cp - 0x1D60F;
			} else if (cp >= 0x1D68A && cp <= 0x1D6A3) { // Mapped11: 26
				ret = cp - 0x1D629;
			} else if (cp >= 0x1D6A8 && cp <= 0x1D6B8) { // Mapped11: 17
				ret = cp - 0x1D2F7;
			}
		} else if (cp <= 0x1D7A0) {
			if (cp >= 0x1D6BA && cp <= 0x1D6C0) { // Mapped11: 7
				ret = cp - 0x1D2F7;
			} else if (cp >= 0x1D6C2 && cp <= 0x1D6D2) { // Mapped11: 17
				ret = cp - 0x1D311;
			} else if (cp >= 0x1D6D4 && cp <= 0x1D6DA) { // Mapped11: 7
				ret = cp - 0x1D311;
			} else if (cp >= 0x1D6E2 && cp <= 0x1D6F2) { // Mapped11: 17
				ret = cp - 0x1D331;
			} else if (cp >= 0x1D6F4 && cp <= 0x1D6FA) { // Mapped11: 7
				ret = cp - 0x1D331;
			} else if (cp >= 0x1D6FC && cp <= 0x1D70C) { // Mapped11: 17
				ret = cp - 0x1D34B;
			} else if (cp >= 0x1D70E && cp <= 0x1D714) { // Mapped11: 7
				ret = cp - 0x1D34B;
			} else if (cp >= 0x1D71C && cp <= 0x1D72C) { // Mapped11: 17
				ret = cp - 0x1D36B;
			} else if (cp >= 0x1D72E && cp <= 0x1D734) { // Mapped11: 7
				ret = cp - 0x1D36B;
			} else if (cp >= 0x1D736 && cp <= 0x1D746) { // Mapped11: 17
				ret = cp - 0x1D385;
			} else if (cp >= 0x1D748 && cp <= 0x1D74E) { // Mapped11: 7
				ret = cp - 0x1D385;
			} else if (cp >= 0x1D756 && cp <= 0x1D766) { // Mapped11: 17
				ret = cp - 0x1D3A5;
			} else if (cp >= 0x1D768 && cp <= 0x1D76E) { // Mapped11: 7
				ret = cp - 0x1D3A5;
			} else if (cp >= 0x1D770 && cp <= 0x1D780) { // Mapped11: 17
				ret = cp - 0x1D3BF;
			} else if (cp >= 0x1D782 && cp <= 0x1D788) { // Mapped11: 7
				ret = cp - 0x1D3BF;
			} else if (cp >= 0x1D790 && cp <= 0x1D7A0) { // Mapped11: 17
				ret = cp - 0x1D3DF;
			}
		} else if (cp <= 0x1FBF9) {
			if (cp >= 0x1D7A2 && cp <= 0x1D7A8) { // Mapped11: 7
				ret = cp - 0x1D3DF;
			} else if (cp >= 0x1D7AA && cp <= 0x1D7BA) { // Mapped11: 17
				ret = cp - 0x1D3F9;
			} else if (cp >= 0x1D7BC && cp <= 0x1D7C2) { // Mapped11: 7
				ret = cp - 0x1D3F9;
			} else if (cp >= 0x1D7CE && cp <= 0x1D7D7) { // Mapped11: 10
				ret = cp - 0x1D79E;
			} else if (cp >= 0x1D7D8 && cp <= 0x1D7E1) { // Mapped11: 10
				ret = cp - 0x1D7A8;
			} else if (cp >= 0x1D7E2 && cp <= 0x1D7EB) { // Mapped11: 10
				ret = cp - 0x1D7B2;
			} else if (cp >= 0x1D7EC && cp <= 0x1D7F5) { // Mapped11: 10
				ret = cp - 0x1D7BC;
			} else if (cp >= 0x1D7F6 && cp <= 0x1D7FF) { // Mapped11: 10
				ret = cp - 0x1D7C6;
			} else if (cp >= 0x1D800 && cp <= 0x1D9FF) { // Valid
				ret = cp;
			} else if (cp >= 0x1E900 && cp <= 0x1E921) { // Mapped11: 34
				ret = cp + 0x22;
			} else if (cp >= 0x1EE0A && cp <= 0x1EE0D) { // Mapped11: 4
				ret = cp - 0x1E7C7;
			} else if (cp >= 0x1EE2A && cp <= 0x1EE2D) { // Mapped11: 4
				ret = cp - 0x1E7E7;
			} else if (cp >= 0x1EE8B && cp <= 0x1EE8D) { // Mapped11: 3
				ret = cp - 0x1E847;
			} else if (cp >= 0x1EEAB && cp <= 0x1EEAD) { // Mapped11: 3
				ret = cp - 0x1E867;
			} else if (cp >= 0x1F130 && cp <= 0x1F149) { // Mapped11: 26
				ret = cp - 0x1F0CF;
			} else if (cp >= 0x1FBF0 && cp <= 0x1FBF9) { // Mapped11: 10
				ret = cp - 0x1FBC0;
			}
		} else {
			if (cp >= 0x20000 && cp <= 0x2A6DF) { // Valid
				ret = cp;
			} else if (cp >= 0x2A700 && cp <= 0x2B738) { // Valid
				ret = cp;
			} else if (cp >= 0x2B820 && cp <= 0x2CEA1) { // Valid
				ret = cp;
			} else if (cp >= 0x2CEB0 && cp <= 0x2EBE0) { // Valid
				ret = cp;
			} else if (cp >= 0x30000 && cp <= 0x3134A) { // Valid
				ret = cp;
			}
		}
	}

}