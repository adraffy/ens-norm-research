import {readFileSync, writeFileSync} from 'node:fs';
import {CHARS} from '@adraffy/ensip-norm';

function read_json(name) {
	return JSON.parse(readFileSync(new URL(`${name}.json`, import.meta.url)));
}

let cps = [...new Set([
    read_json('DerivedNormalizationProps').NFC_QC.flatMap(x => parse_cp_range(x[0])),
    Object.entries(read_json('DerivedCombiningClass')).flatMap(([k, v]) => parseInt(k) > 0 ? v.flatMap(parse_cp_range) : [])
].flat())].sort((a, b) => a - b);


writeFileSync(new URL(`./nfc-check.js`, import.meta.url), [
    `// created ${new Date().toJSON()}`,
    `// derived from DerivedNormalizationProps.NFC_QC (where N/M) + DerivedCombiningClass (where class > 0)`,
    `export default ${JSON.stringify(cps)};`
].join('\n'));


export function parse_cp(s) {
    let cp = parseInt(s, 16);
    if (!Number.isSafeInteger(cp) || cp < 0) throw new TypeError(`expected code point: ${s}`);
    return cp;
}

// "AAAA"       => [0xAAAA]
// "AAAA..AAAC" => [0xAAAA, 0xAAAB, 0xAAAC]
export function parse_cp_range(s) {
    let pos = s.indexOf('..');
    if (pos >= 0) {
        let lo = parse_cp(s.slice(0, pos));
        let hi = parse_cp(s.slice(pos + 2));
        if (hi < lo) throw new Error(`expected non-empty range: ${s}`);
        return Array(hi - lo + 1).fill().map((_, i) => lo + i);
    } else {
        return [parse_cp(s)];
    }
}