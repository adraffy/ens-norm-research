# ENS Normalization Research

## /idna2003-qc/

On-chain normalization following [@adraffy/ensip-norm/](https://github.com/adraffy/ensip-norm).

Currently fails incorrectly when [`NFC_QC`](https://unicode.org/reports/tr15/#Detecting_Normalization_Forms) is No/Maybe.


Rinkeby Contract: [0x1a29f1e459ccd6667590218f04175fe394324d9d](https://rinkeby.etherscan.io/address/0x1a29f1e459ccd6667590218f04175fe394324d9d#readContract)



1. Deploy `Normalize3.sol`
2. Call `uploadXXX()` with the appropriate payloads