
import {readFileSync} from 'node:fs';
import {nfc, explode_cp} from './nf.js';

const TESTS = JSON.parse(readFileSync(new URL('./NormalizationTest.json', import.meta.url)));

for (let [kind, tests] of Object.entries(TESTS)) {
    console.log(kind, tests.length);
    for (let test of tests) {
        let [s, c, d] = test;
        if (c !== s.normalize('NFC')) throw 1;
        if (d !== s.normalize('NFD')) throw 1;

        if (c !== nfc(s)) {
            console.log(explode_cp(s));
            console.log(explode_cp(s.normalize('NFC')));
            console.log(explode_cp(nfc(s)));

            throw 1;
        }

    }
}
