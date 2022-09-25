// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.15;

contract Test {

    error InvalidEmoji();

    uint24 constant PLACEHOLDER = 0x800000;

    function validate(uint24[] memory v) public pure returns (uint24[] memory u) {
        function (uint24[] memory, uint256) pure returns (uint256) f = state0;
        uint256 i;
        while (i < v.length) {
            uint256 next = f(v, i);
            assembly {
                f := next
                i := add(i, 1)
            }
        }
        u = v;
    }

    function ptr(function (uint24[] memory, uint256) pure returns (uint256) f) private pure returns (uint256 offset) {
        assembly {
            offset := f
        }
    }

    function state0(uint24[] memory cps, uint256 pos) private pure returns (uint256 next) {
        uint256 cp = cps[pos];
        if (is_group1(cp)) {
            cps[pos] = PLACEHOLDER;
            next = ptr(state1);
        } else if (is_group2(cp)) {
            cps[pos] = PLACEHOLDER;
            next = ptr(state0);
        } else if (is_group3(cp)) {
            cps[pos] = PLACEHOLDER;
            next = ptr(state2);
        } else if (cp == 0x1F46F) {
            cps[pos] = PLACEHOLDER;
            next = ptr(state3);
        } else if (cp == 0x1F9DE || cp == 0x1F9DF) {
            cps[pos] = PLACEHOLDER;
            next = ptr(state6);
        } else if (cp == 0x1F9D1) {
            cps[pos] = PLACEHOLDER;
            next = ptr(state7);
        } else if (cp == 0x1F408) {
            cps[pos] = PLACEHOLDER;
            next = ptr(state22);
        } else {
            next = ptr(state0);
        }
    }

    // GROUP1 | ZWJ GENDER
    // GROUP1 | MOD ZWJ GENDER
    // GROUP1 |
    function state1(uint24[] memory cps, uint256 pos) private pure returns (uint256 next) {
        if (is_zwj(cps[pos])) {
            next = ptr(state5);
        } else if (is_mod(cps[pos])) {
            cps[pos] = PLACEHOLDER;
            next = ptr(state4);
        } else {
            next = state0(cps, pos);
        }
    }

    // GROUP3 | MOD
    // GROUP3 | 
    function state2(uint24[] memory cps, uint256 pos) private pure returns (uint256 next) {
        if (is_mod(cps[pos])) {
            cps[pos] = PLACEHOLDER;
            next = ptr(state0);
        } else {
            next = state0(cps, pos);
        }
    }

    // 1F46F | ZWJ GENDER
    // 1F46F | MOD
    // 1F46F |
    function state3(uint24[] memory cps, uint256 pos) private pure returns (uint256 next) {
        if (is_zwj(cps[pos])) {
            next = ptr(state5);            
        } else if (is_mod(cps[pos])) {
            cps[pos] = PLACEHOLDER;
            next = ptr(state0);
        } else {
            next = state0(cps, pos);
        }
    }

    // GROUP1 MOD | ZWJ GENDER
    // GROUP1 MOD |
    function state4(uint24[] memory cps, uint256 pos) private pure returns (uint256 next) {
        if (is_zwj(cps[pos])) {
            next = ptr(state5);
        } else {
            next = state0(cps, pos);
        }
    }

    // GROUP1 MOD | ZWJ GENDER
    function state5(uint24[] memory cps, uint256 pos) private pure returns (uint256 next) {
        if (is_gender(cps[pos])) {
            cps[pos-1] = cps[pos] = PLACEHOLDER;
            next = ptr(state0);
        } else {
            revert InvalidEmoji();
        }
    }

    // [1F9DE|1F9DF] | ZWJ GENDER
    // [1F9DE|1F9DF] |
    function state6(uint24[] memory cps, uint256 pos) private pure returns (uint256 next) {
        if (is_zwj(cps[pos])) {
            next = ptr(state5);
        } else {
            next = state0(cps, pos);
        }
    }

    // 1F9D1 @ | ZWJ SYMBOL25 
    // 1F9D1 @ | ZWJ 1F91D ZWJ 1F9D1 
    // 1F9D1 @ | MOD ZWJ SYMBOL25
    // 1F9D1 @ | MOD ZWJ 2764 ZWJ 1F9D1 MOD2
    // 1F9D1 @ | MOD ZWJ 2764 ZWJ 1F48B ZWJ 1F9D1 MOD2
    // 1F9D1 @ | MOD ZWJ 1F91D ZWJ 1F9D1 MOD
    // 1F9D1 @ | MOD
    // 1F9D1 @ |
    function state7(uint24[] memory cps, uint256 pos) private pure returns (uint256 next) {
        if (is_zwj(cps[pos])) {
            next = ptr(state8);
        } else if (is_mod(cps[pos])) {
            cps[pos] = PLACEHOLDER | cps[pos]; // remember
            next = ptr(state9);
        } else {
            next = state0(cps, pos);
        }
    }

    // 1F9D1 @ ZWJ | SYMBOL25 
    // 1F9D1 @ ZWJ | 1F91D ZWJ 1F9D1 
    function state8(uint24[] memory cps, uint256 pos) private pure returns (uint256 next) {
        if (is_symbol25(cps[pos])) {
            cps[pos-1] = cps[pos] = PLACEHOLDER;
            next = ptr(state0);
        } else if (cps[pos] == 0x1F91D) {
            next = ptr(state10);
        } else {
            next = state0(cps, pos);
        }
    }

    // 1F9D1 @ ZWJ 1F91D | ZWJ 1F9D1 
    function state10(uint24[] memory cps, uint256 pos) private pure returns (uint256 next) {
        if (is_zwj(cps[pos])) {
            next = ptr(state12);
        } else {
            revert InvalidEmoji();
        }
    }

    // 1F9D1 @ ZWJ 1F91D ZWJ | 1F9D1 
    function state12(uint24[] memory cps, uint256 pos) private pure returns (uint256 next) {
        if (cps[pos] == 0x1F9D1) {
            cps[pos-3] = cps[pos-2] = cps[pos-1] = cps[pos] = PLACEHOLDER;
            next = ptr(state0);
        } else {
            revert InvalidEmoji();
        }
    }

    // 1F9D1 MOD @ | ZWJ SYMBOL25
    // 1F9D1 MOD @ | ZWJ 2764 ZWJ 1F9D1 MOD2
    // 1F9D1 MOD @ | ZWJ 2764 ZWJ 1F48B ZWJ 1F9D1 MOD2
    // 1F9D1 MOD @ | ZWJ 1F91D ZWJ 1F9D1 MOD
    // 1F9D1 MOD @ |
    function state9(uint24[] memory cps, uint256 pos) private pure returns (uint256 next) {
        if (is_zwj(cps[pos])) {
            next = ptr(state11);
        } else {
            next = state0(cps, pos);
        }
    }

    // 1F9D1 MOD @ ZWJ | SYMBOL25
    // 1F9D1 MOD @ ZWJ | 2764 ZWJ 1F9D1 MOD2
    // 1F9D1 MOD @ ZWJ | 2764 ZWJ 1F48B ZWJ 1F9D1 MOD2
    // 1F9D1 MOD @ ZWJ | 1F91D ZWJ 1F9D1 MOD
    function state11(uint24[] memory cps, uint256 pos) private pure returns (uint256 next) {
        if (is_symbol25(cps[pos])) {
            cps[pos-1] = cps[pos] = PLACEHOLDER;
            next = ptr(state0);
        } else if (cps[pos] == 0x2764) {
            next = ptr(state13);
        } else if (cps[pos] == 0x1F91D) {
            next = ptr(state14);
        } else {
            revert InvalidEmoji();
        }
    }

    // 1F9D1 MOD @ ZWJ 2764 | ZWJ 1F9D1 MOD2
    // 1F9D1 MOD @ ZWJ 2764 | ZWJ 1F48B ZWJ 1F9D1 MOD2
    function state13(uint24[] memory cps, uint256 pos) private pure returns (uint256 next) {
        if (is_zwj(cps[pos])) {
            next = ptr(state15);
        } else {
            revert InvalidEmoji();
        }
    }

    // 1F9D1 MOD @ ZWJ 2764 ZWJ | 1F9D1 MOD2
    // 1F9D1 MOD @ ZWJ 2764 ZWJ | 1F48B ZWJ 1F9D1 MOD2
    function state15(uint24[] memory cps, uint256 pos) private pure returns (uint256 next) {
        if (cps[pos] == 0x1F9D1) {
            next = ptr(state17);
        } else if (cps[pos] == 0x1F48B) {
            next = ptr(state18);
        } else {
            revert InvalidEmoji();
        }
    }

    // 1F9D1 MOD @ ZWJ 2764 ZWJ 1F9D1 | MOD2
    function state17(uint24[] memory cps, uint256 pos) private pure returns (uint256 next) {
        if (is_mod2(cps, pos-5, pos)) {
            cps[pos-4] = cps[pos-3] = cps[pos-2] = cps[pos-1] = cps[pos] = PLACEHOLDER;
            next = ptr(state0);
        } else {
            revert InvalidEmoji();
        }
    }

    // 1F9D1 MOD @ ZWJ 2764 ZWJ 1F48B | ZWJ 1F9D1 MOD2
    function state18(uint24[] memory cps, uint256 pos) private pure returns (uint256 next) {
        if (is_zwj(cps[pos])) {
            next = ptr(state20);
        } else {
            revert InvalidEmoji();
        }
    }

    // 1F9D1 MOD @ ZWJ 2764 ZWJ 1F48B ZWJ | 1F9D1 MOD2
    function state20(uint24[] memory cps, uint256 pos) private pure returns (uint256 next) {
        if (cps[pos] == 0x1F9D1) {
            next = ptr(state21);
        } else {
            revert InvalidEmoji();
        }
    }

    // 1F9D1 MOD @ ZWJ 2764 ZWJ 1F48B ZWJ 1F9D1 | MOD2
    function state21(uint24[] memory cps, uint256 pos) private pure returns (uint256 next) {
        if (is_mod2(cps, pos-7, pos)) {
            cps[pos-6] = cps[pos-5] = cps[pos-4] = cps[pos-3] = cps[pos-2] = cps[pos-1] = cps[pos] = PLACEHOLDER;
            next = ptr(state0);
        } else {
            revert InvalidEmoji();
        }
    }

    // 1F9D1 MOD @ ZWJ 1F91D | ZWJ 1F9D1 MOD
    function state14(uint24[] memory cps, uint256 pos) private pure returns (uint256 next) {
        if (is_zwj(cps[pos])) {
            next = ptr(state16);
        } else {
            revert InvalidEmoji();
        }
    }

    // 1F9D1 MOD @ ZWJ 1F91D ZWJ | 1F9D1 MOD
    function state16(uint24[] memory cps, uint256 pos) private pure returns (uint256 next) {
        if (cps[pos] == 0x1F9D1) {
            next = ptr(state19);
        } else {
            revert InvalidEmoji();
        }
    }

    // 1F9D1 MOD @ ZWJ 1F91D ZWJ 1F9D1 | MOD
    function state19(uint24[] memory cps, uint256 pos) private pure returns (uint256 next) {
        if (is_mod(cps[pos])) {
            cps[pos-4] = cps[pos-3] = cps[pos-2] = cps[pos-1] = cps[pos] = PLACEHOLDER;
            next = ptr(state0);
        } else {
            revert InvalidEmoji();
        }
    }

    // 1F408 @ | ZWJ 2B1B
    // 1F408 @ |
    function state22(uint24[] memory cps, uint256 pos) private pure returns (uint256 next) {
        if (is_zwj(cps[pos])) {
            next = ptr(state23);
        } else {
            next = state0(cps, pos);
        }
    }

    // 1F408 @ ZWJ | 2B1B
    function state23(uint24[] memory cps, uint256 pos) private pure returns (uint256 next) {
        if (cps[pos] == 0x2B1B) {
            cps[pos-1] = cps[pos] = PLACEHOLDER;
            next = ptr(state0);
        } else {
            revert InvalidEmoji();
        }
    }
    
    function is_zwj(uint256 x) private pure returns (bool) {
        return x == 0x200D;
    }

    function is_mod(uint256 x) private pure returns (bool) {
        return x >= 0x1F3FB && x <= 0x1F3FF;
    }

    function is_mod2(uint24[] memory cps, uint256 a, uint256 b) private pure returns (bool) {
        uint256 cp = cps[b];
        return is_mod(cp) && cps[a] != (PLACEHOLDER | cp);
    }

    function is_gender(uint256 x) private pure returns (bool) {
        return x == 0x2640 || x == 0x2642;
    }

    function is_symbol24(uint256 x) private pure returns (bool) {
        return x == 0x2695
            || x == 0x2696
            || x == 0x2708
            || x == 0x1F33E
            || x == 0x1F373
            || x == 0x1F37C
            || x == 0x1F393
            || x == 0x1F3A4
            || x == 0x1F3A8
            || x == 0x1F3EB
            || x == 0x1F3ED
            || x == 0x1F4BB
            || x == 0x1F4BC
            || x == 0x1F527
            || x == 0x1F52C
            || x == 0x1F680
            || x == 0x1F692
            || x >= 0x1F9AF && x <= 0x1F9B3
            || x == 0x1F9BC
            || x == 0x1F9BD;
    }

    function is_symbol25(uint256 x) private pure returns (bool) {
        return is_symbol24(x) || x == 0x1F384;
    }

    function is_symbol26(uint256 x) private pure returns (bool) {
        return is_symbol24(x) || x == 0x1F466 || x == 0x1F467;
    }

    function is_group1(uint256 x) private pure returns (bool) {
        return x == 0x26F9
            || x == 0x1F3C3
            || x == 0x1F3C4
            || x >= 0x1F3CA && x <= 0x1F3CC
            || x == 0x1F46E
            || x == 0x1F470
            || x == 0x1F471
            || x == 0x1F473
            || x == 0x1F477
            || x == 0x1F481
            || x == 0x1F482
            || x == 0x1F486
            || x == 0x1F487
            || x == 0x1F575
            || x >= 0x1F645 && x <= 0x1F647
            || x == 0x1F64B
            || x == 0x1F64D
            || x == 0x1F64E
            || x == 0x1F6A3
            || x >= 0x1F6B4 && x <= 0x1F6B6
            || x == 0x1F926
            || x == 0x1F935
            || x >= 0x1F937 && x <= 0x1F939
            || x >= 0x1F93C && x <= 0x1F93E
            || x == 0x1F9B8
            || x == 0x1F9B9
            || x >= 0x1F9CD && x <= 0x1F9CF
            || x == 0x1F9D4
            || x >= 0x1F9D6 && x <= 0x1F9DD; 
    }

    function is_group2(uint256 x) private pure returns (bool) {
        return x == 0x261D
            || x >= 0x270A && x <= 0x270D
            || x == 0x1F385
            || x == 0x1F3C2
            || x == 0x1F3C7
            || x == 0x1F442
            || x == 0x1F443
            || x >= 0x1F446 && x <= 0x1F450
            || x == 0x1F466
            || x == 0x1F467
            || x >= 0x1F46A && x <= 0x1F46D
            || x == 0x1F472
            || x >= 0x1F474 && x <= 0x1F476
            || x == 0x1F478
            || x == 0x1F47C
            || x == 0x1F483
            || x == 0x1F485
            || x == 0x1F48F
            || x == 0x1F491
            || x == 0x1F4AA
            || x == 0x1F574
            || x == 0x1F57A
            || x == 0x1F590
            || x == 0x1F595
            || x == 0x1F596
            || x == 0x1F64C
            || x == 0x1F64F
            || x == 0x1F6C0
            || x == 0x1F6CC
            || x == 0x1F90C
            || x == 0x1F90F
            || x >= 0x1F918 && x <= 0x1F91F
            || x >= 0x1F930 && x <= 0x1F934
            || x == 0x1F936
            || x == 0x1F977
            || x == 0x1F9B5
            || x == 0x1F9B6
            || x == 0x1F9BB
            || x == 0x1F9D2
            || x == 0x1F9D3
            || x == 0x1F9D5
            || x >= 0x1FAC3 && x <= 0x1FAC5
            || x == 0x1FAF0
            || x >= 0x1FAF2 && x <= 0x1FAF6; 
    }

    function is_group3(uint256 x) private pure returns (bool) {
        return x == 0xA9
            || x == 0xAE
            || x == 0x203C
            || x == 0x2049
            || x >= 0x2194 && x <= 0x2199
            || x == 0x21A9
            || x == 0x21AA
            || x == 0x231A
            || x == 0x231B
            || x == 0x2328
            || x == 0x23CF
            || x >= 0x23E9 && x <= 0x23F3
            || x >= 0x23F8 && x <= 0x23FA
            || x == 0x25AA
            || x == 0x25AB
            || x == 0x25B6
            || x == 0x25C0
            || x >= 0x25FB && x <= 0x25FE
            || x >= 0x2600 && x <= 0x2604
            || x == 0x260E
            || x == 0x2611
            || x == 0x2614
            || x == 0x2615
            || x == 0x2618
            || x == 0x2620
            || x == 0x2622
            || x == 0x2623
            || x == 0x2626
            || x == 0x262A
            || x == 0x262E
            || x == 0x262F
            || x >= 0x2638 && x <= 0x263A
            || x == 0x2640
            || x == 0x2642
            || x >= 0x2648 && x <= 0x2653
            || x == 0x265F
            || x == 0x2660
            || x == 0x2663
            || x == 0x2665
            || x == 0x2666
            || x == 0x2668
            || x == 0x267B
            || x == 0x267E
            || x == 0x267F
            || x >= 0x2692 && x <= 0x2697
            || x == 0x2699
            || x == 0x269B
            || x == 0x269C
            || x == 0x26A0
            || x == 0x26A1
            || x == 0x26A7
            || x == 0x26AA
            || x == 0x26AB
            || x == 0x26B0
            || x == 0x26B1
            || x == 0x26BD
            || x == 0x26BE
            || x == 0x26C4
            || x == 0x26C5
            || x == 0x26C8
            || x == 0x26CE
            || x == 0x26CF
            || x == 0x26D1
            || x == 0x26D3
            || x == 0x26D4
            || x == 0x26E9
            || x == 0x26EA
            || x >= 0x26F0 && x <= 0x26F5
            || x == 0x26F7
            || x == 0x26F8
            || x == 0x26FA
            || x == 0x26FD
            || x == 0x2702
            || x == 0x2705
            || x == 0x2708
            || x == 0x2709
            || x == 0x270F
            || x == 0x2712
            || x == 0x2714
            || x == 0x2716
            || x == 0x271D
            || x == 0x2721
            || x == 0x2728
            || x == 0x2733
            || x == 0x2734
            || x == 0x2744
            || x == 0x2747
            || x == 0x274C
            || x == 0x274E
            || x >= 0x2753 && x <= 0x2755
            || x == 0x2757
            || x == 0x2763
            || x >= 0x2795 && x <= 0x2797
            || x == 0x27A1
            || x == 0x27B0
            || x == 0x27BF
            || x == 0x2934
            || x == 0x2935
            || x >= 0x2B05 && x <= 0x2B07
            || x == 0x2B1B
            || x == 0x2B1C
            || x == 0x2B50
            || x == 0x2B55
            || x == 0x3030
            || x == 0x303D
            || x == 0x1F004
            || x == 0x1F0CF
            || x == 0x1F170
            || x == 0x1F171
            || x == 0x1F17E
            || x == 0x1F17F
            || x == 0x1F18E
            || x >= 0x1F191 && x <= 0x1F19A
            || x >= 0x1F1E6 && x <= 0x1F1FF
            || x >= 0x1F300 && x <= 0x1F321
            || x >= 0x1F324 && x <= 0x1F384
            || x >= 0x1F386 && x <= 0x1F393
            || x == 0x1F396
            || x == 0x1F397
            || x >= 0x1F399 && x <= 0x1F39B
            || x >= 0x1F39E && x <= 0x1F3C1
            || x == 0x1F3C5
            || x == 0x1F3C6
            || x == 0x1F3C8
            || x == 0x1F3C9
            || x >= 0x1F3CD && x <= 0x1F3F0
            || x == 0x1F3F5
            || x >= 0x1F3F7 && x <= 0x1F407
            || x >= 0x1F409 && x <= 0x1F414
            || x >= 0x1F416 && x <= 0x1F43A
            || x >= 0x1F43C && x <= 0x1F440
            || x == 0x1F444
            || x == 0x1F445
            || x >= 0x1F451 && x <= 0x1F465
            || x >= 0x1F479 && x <= 0x1F47B
            || x >= 0x1F47D && x <= 0x1F480
            || x == 0x1F484
            || x >= 0x1F488 && x <= 0x1F48E
            || x == 0x1F490
            || x >= 0x1F492 && x <= 0x1F4A9
            || x >= 0x1F4AB && x <= 0x1F4FD
            || x >= 0x1F4FF && x <= 0x1F53D
            || x >= 0x1F549 && x <= 0x1F54E
            || x >= 0x1F550 && x <= 0x1F567
            || x == 0x1F56F
            || x == 0x1F570
            || x == 0x1F573
            || x >= 0x1F576 && x <= 0x1F579
            || x == 0x1F587
            || x >= 0x1F58A && x <= 0x1F58D
            || x == 0x1F5A4
            || x == 0x1F5A5
            || x == 0x1F5A8
            || x == 0x1F5B1
            || x == 0x1F5B2
            || x == 0x1F5BC
            || x >= 0x1F5C2 && x <= 0x1F5C4
            || x >= 0x1F5D1 && x <= 0x1F5D3
            || x >= 0x1F5DC && x <= 0x1F5DE
            || x == 0x1F5E1
            || x == 0x1F5E3
            || x == 0x1F5E8
            || x == 0x1F5EF
            || x == 0x1F5F3
            || x >= 0x1F5FA && x <= 0x1F62D
            || x >= 0x1F62F && x <= 0x1F634
            || x >= 0x1F637 && x <= 0x1F644
            || x >= 0x1F648 && x <= 0x1F64A
            || x >= 0x1F680 && x <= 0x1F6A2
            || x >= 0x1F6A4 && x <= 0x1F6B3
            || x >= 0x1F6B7 && x <= 0x1F6BF
            || x >= 0x1F6C1 && x <= 0x1F6C5
            || x == 0x1F6CB
            || x >= 0x1F6CD && x <= 0x1F6D2
            || x >= 0x1F6D5 && x <= 0x1F6D7
            || x >= 0x1F6DD && x <= 0x1F6E5
            || x == 0x1F6E9
            || x == 0x1F6EB
            || x == 0x1F6EC
            || x == 0x1F6F0
            || x >= 0x1F6F3 && x <= 0x1F6FC
            || x >= 0x1F7E0 && x <= 0x1F7EB
            || x == 0x1F7F0
            || x == 0x1F90D
            || x == 0x1F90E
            || x >= 0x1F910 && x <= 0x1F917
            || x >= 0x1F920 && x <= 0x1F925
            || x >= 0x1F927 && x <= 0x1F92F
            || x == 0x1F93A
            || x >= 0x1F93F && x <= 0x1F945
            || x >= 0x1F947 && x <= 0x1F976
            || x >= 0x1F978 && x <= 0x1F9B4
            || x == 0x1F9B7
            || x == 0x1F9BA
            || x >= 0x1F9BC && x <= 0x1F9CC
            || x == 0x1F9D0
            || x >= 0x1F9E0 && x <= 0x1F9FF
            || x >= 0x1FA70 && x <= 0x1FA74
            || x >= 0x1FA78 && x <= 0x1FA7C
            || x >= 0x1FA80 && x <= 0x1FA86
            || x >= 0x1FA90 && x <= 0x1FAAC
            || x >= 0x1FAB0 && x <= 0x1FABA
            || x >= 0x1FAC0 && x <= 0x1FAC2
            || x >= 0x1FAD0 && x <= 0x1FAD9
            || x >= 0x1FAE0 && x <= 0x1FAE7; 
    }
            
}