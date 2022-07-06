# ENS Normalization Research

## /idna2003-qc/

On-chain normalization following [@adraffy/ensip-norm/](https://github.com/adraffy/ensip-norm).

Currently fails incorrectly when [`NFC_QC`](https://unicode.org/reports/tr15/#Detecting_Normalization_Forms) is No/Maybe.

Rinkeby Contract: [0x335be342669ae015d7a87eb7c632447f9218254b](https://rinkeby.etherscan.io/address/0x335be342669ae015d7a87eb7c632447f9218254b#readContract)


1. Deploy `Normalize3.sol`
2. Call `uploadXXX()` with the appropriate payloads