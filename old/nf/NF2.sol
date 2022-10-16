/// @author raffy.eth
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Ownable} from "@openzeppelin/contracts@4.6.0/access/Ownable.sol";

contract NF is Ownable {
                
    function nfd(string memory s) public view returns (uint256[] memory cps0, uint256[] memory cps1, string memory ret) {
        cps0 = _decodeUTF8(bytes(s));
        cps1 = _nfd(cps0);
        ret = string(_encodeUTF8(cps1));
    }


    function debugDestroy() onlyOwner public {
		selfdestruct(payable(msg.sender));
	}

    mapping (uint256 => uint256) _decomp;
    mapping (uint256 => uint256) _class;

    function updateDecomp(bytes calldata data) public onlyOwner {
		updateMapping(_decomp, data, 3);
	}
    function updateClass(bytes calldata data) public onlyOwner {
        updateMapping(_class, data, 2);
    }

	function updateMapping(mapping (uint256 => uint256) storage map, bytes calldata data, uint256 key_bytes) private {
		uint256 i;
		uint256 e;
	    uint256 mask = ~(type(uint256).max << (key_bytes << 3));
		assembly {
			i := data.offset
			e := add(i, data.length)
		}
		while (i < e) {
			uint256 k;
			uint256 v;
			assembly {
				// key-value pairs are packed in reverse 
				// eg. [value1][key1][value2][key2]...
				v := calldataload(i)
				i := add(i, key_bytes)
				k := and(calldataload(i), mask)
				i := add(i, 32)
			}
			map[k] = v;
		}
	}

    function _getClass(uint256 cp) public view returns (uint256) {
		return (_class[cp >> 5] >> ((cp & 0x1F) << 3)) & 0xFF;
	}

    function _getDecomp(uint256 cp) public view returns (uint256) {
        return (_decomp[cp >> 2] >> ((cp & 0x3) << 6)) & 0xFFFFFFFFFFFFFFFF;
    }

    // https://www.unicode.org/versions/Unicode14.0.0/ch03.pdf
    uint256 constant S0 = 0xAC00;
    uint256 constant L0 = 0x1100;
    uint256 constant V0 = 0x1161;
    uint256 constant T0 = 0x11A7;
    uint256 constant L_COUNT = 19;
    uint256 constant V_COUNT = 21;
    uint256 constant T_COUNT = 28;
    uint256 constant N_COUNT = V_COUNT * T_COUNT;
    uint256 constant S_COUNT = L_COUNT * N_COUNT;
    uint256 constant S1 = S0 + S_COUNT;
    uint256 constant L1 = L0 + L_COUNT;
    uint256 constant V1 = V0 + V_COUNT;
    uint256 constant T1 = T0 + T_COUNT;
    uint256 constant CP_MASK = 0xFFFFFF;

    function _isHangul(uint256 cp) private pure returns (bool) {
        return cp >= S0 && cp < S1;
    }

    function _decodeUTF8(bytes memory src) private pure returns (uint256[] memory ret) {
        ret = new uint256[](src.length);
        uint256 ptr;
        assembly {
            ptr := src
        }
        uint256 len;
        uint256 end = ptr + src.length;
        while (ptr < end) {
            (uint256 cp, uint256 step, ) = _readUTF8(ptr);
            ret[len++] = cp;
            ptr += step;            
        }
        assembly {
            mstore(ret, len) // truncate
        }
    }
    
    function _encodeUTF8(uint256[] memory cps) private pure returns (bytes memory ret) {
        ret = new bytes(cps.length << 2);
        uint256 ret_off;
        assembly {
            ret_off := add(ret, 32)
        }
        uint256 ret_end = ret_off;
        for (uint256 i; i < cps.length; i++) {
            ret_end = _writeUTF8(ret_end, cps[i] & CP_MASK);
        }
        assembly {
            mstore(ret, sub(ret_end, ret_off))
        }
    }


	function _writeBytes(uint256 ptr, uint256 buf, uint256 len) private pure returns (uint256 ptr1) {
        uint256 mask = type(uint256).max << (len << 3);
		assembly {
			ptr1 := add(ptr, len) // advance
			mstore(ptr1, or(and(mload(ptr1), mask), and(buf, not(mask)))) // merge and store
		}
	}

    function _writeU32(uint256 ptr, uint256 x) private pure returns (uint256) {
        return _writeBytes(ptr, x, 4);
    }

    function _addClass(uint256 cp) private view returns (uint256) {
        return (_getClass(cp) << 24) | cp;
    }

    function _nfd(uint256[] memory cps) private view returns (uint256[] memory ret) {
        ret = new uint256[](cps.length * 3); // growth factor
        uint256 len;
        uint256 has_nz_class;
        for (uint256 i; i < cps.length; i++) {
            uint256 buf = cps[i];
            uint256 width = 32;
            while (width != 0) {
                uint256 cp = buf & 0xFFFFFFFF;
                buf >>= 32;
                width -= 32;
                if (cp < 0x80) {
                    ret[len++] = cp;
                } else if (_isHangul(cp)) {
                    uint256 s_index = cp - S0;
                    uint256 l_index = s_index / N_COUNT | 0;
                    uint256 v_index = (s_index % N_COUNT) / T_COUNT | 0;
                    uint256 t_index = s_index % T_COUNT;
                    uint256 l_cp = _addClass(L0 + l_index);
                    uint256 v_cp = _addClass(V0 + v_index);
                    ret[len++] = l_cp;
                    ret[len++] = v_cp;
                    if (has_nz_class == 0 && (l_cp | v_cp) > CP_MASK) has_nz_class = 1;
                    if (t_index != 0) {              
                        uint256 t_cp = _addClass(T0 + t_index);
                        if (has_nz_class == 0 && t_cp > CP_MASK) has_nz_class = 1;
                        ret[len++] = t_cp;
                    }
                } else {
                    uint256 decomp = _getDecomp(cp);
                    if (decomp != 0) {
                        buf |= (decomp << width);
                        width += (decomp >> 32) == 0 ? 32 : 64;
                    } else {
                        uint256 x_cp = _addClass(cp);
                        if (has_nz_class == 0 && x_cp > CP_MASK) has_nz_class = 1;
                        ret[len++] = x_cp;
                    }
                }
            }
        }
        if (has_nz_class != 0) {
            uint256 prev = ret[0] >> 24;
            for (uint256 i = 1; i < len; i++) {
                uint256 rank = ret[i] >> 24;
                if (prev == 0 || rank == 0 || prev <= rank) {
                    prev = rank;
                    continue;
                }
                uint256 j = i - 1;
                while (true) {
                    (ret[j+1], ret[j]) = (ret[j], ret[j+1]);
                    if (j == 0) break;
                    prev = ret[--j] >> 24;
                    if (prev <= rank) break;
                }
                prev = ret[i] >> 24;
            }
        }
        assembly {
            mstore(ret, len) // truncate
        }
    }

	function _readUTF8(uint256 ptr) private pure returns (uint256 cp, uint256 step, uint256 raw) {
		// 0xxxxxxx => 1 :: 0aaaaaaa ???????? ???????? ???????? => 0aaaaaaa
		// 110xxxxx => 2 :: 110aaaaa 10bbbbbb ???????? ???????? => 00000aaa aabbbbbb
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

    function _writeUTF8(uint256 ptr, uint256 cp) private pure returns (uint256) {		
		if (cp < 0x80) {
            assembly {
                mstore8(ptr, cp)
            }
            return ptr + 1;
		}
		if (cp < 0x800) {
            assembly {
                mstore8(ptr,         or(0xC0, shr(6, cp)))
                mstore8(add(ptr, 1), or(0x80, and(cp, 0x3F)))
            }
            return ptr + 2;
		} else if (cp < 0x10000) {
            assembly {
                mstore8(ptr,         or(0xE0, shr(12, cp)))
                mstore8(add(ptr, 1), or(0x80, and(shr(6, cp), 0x3F)))
                mstore8(add(ptr, 2), or(0x80, and(cp, 0x3F)))
            }
            return ptr + 3;
		} else {
            assembly {
                mstore8(ptr,         or(0xF0, shr(18, cp)))
                mstore8(add(ptr, 1), or(0x80, and(shr(12, cp), 0x3F)))
                mstore8(add(ptr, 2), or(0x80, and(shr(6, cp), 0x3F)))
                mstore8(add(ptr, 3), or(0x80, and(cp, 0x3F)))
            }
            return ptr + 4;
		}
	}

}