// https://www.unicode.org/reports/tr15/#Implementation_Notes

// https://github.com/knu/ruby-unf_ext/blob/master/ext/unf_ext/unf/normalizer.hh

import {readFile} from 'node:fs/promises';
import {CHARS} from '@adraffy/ensip-norm';

async function read_json(name) {
	return JSON.parse(await readFile(new URL(`${name}.json`, import.meta.url)));
}

// hex to dec
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

export function explode_cp(s) {
	return [...s].map(x => x.codePointAt(0));
}


let input_set = new Set([...CHARS.valid, ...CHARS.mapped.map(x => x[0])]); // 912 unchanged


const EXCLUSIONS = (await read_json('CompositionExclusions')).flatMap(parse_cp_range);

const QC = {};
for (let [range, type] of (await read_json('DerivedNormalizationProps')).NFC_QC) {
	for (let cp of parse_cp_range(range)) {
		QC[cp] = type;
	}
}




console.log(JSON.stringify((await read_json('DerivedNormalizationProps')).NFC_QC.map(x => x[0])));

//let cc = Object.fromEntries(Object.entries(await read_json('DerivedCombiningClass')).map(([k, v]) => [k, v.flatMap(parse_cp_range)]));
const CC = {};
for (let [cls, v] of Object.entries(await read_json('DerivedCombiningClass'))) {
	cls = parseInt(cls);
	if (cls == 0) continue;
	for (let s of v) {
		for (let cp of parse_cp_range(s)) {
			CC[cp] = cls;
		}
	}
}

export function quick_check(s) {
	let cls0 = 0;
	let ret = true;
	for (let cp of explode_cp(s)) {
		let cls = CC[cp] ?? 0;
		if (cls0 > cls && cls != 0) return false;
		switch (QC[cp]) {
			case 'N': return false;
			case 'M': ret = undefined;
		}		
		cls0 = cls;
	}
	return ret;
}

export function nfc(s) {
	let cls0 = 0;
	let start = -1;
	let sorted;
	let cps = explode_cp(s);
	let output = [];

	//console.log(cps.map(cp => [cp, CC[cp] ?? 0, QC[cp] ?? 'Y']));

	let last_cp;
	for (let i = 0; i < cps.length; i++) {
		let cp = cps[i];
		let cls = CC[cp] ?? 0;
		if (start >= 0) {
			if (cls == 0) {
				repair(i);
				start = -1;
				last_cp = cp;
			} else if (sorted) {
				if (cls < cls0) {
					sorted = false;
				} else {
					cls0 = cls;
				}
			}
		} else {
			if (cls > 0 || QC[cp]) {
				start = Math.max(0, i - 1);
				cls0 = cls;
				sorted = true;
			} else {
				if (last_cp >= 0) {
					output.push(last_cp);
				}
				last_cp = cp;
			}
		}
	}
	if (start >= 0) {
		repair(cps.length);
	} else if (last_cp >= 0) {
		output.push(last_cp);
	}
	return String.fromCodePoint(...output);
	function repair(end) {
		let slice = cps.slice(start, end);
		if (!sorted) {
			slice.sort((a, b) => {
				let ca = CC[a] ?? 0;
				let cb = CC[b] ?? 0;
				return ca - cb;
			});
		}
		output.push(...explode_cp(String.fromCodePoint(...slice).normalize('NFC')));
	}
}

function next_invalid(cps, pos) {
	let starter = pos;
	let cls0 = 0;
	while (pos < cps.length) {
		let cp = cps[pos];
		let cls = CC[cp] ?? 0;
		if (cls0 > cls && cls != 0) break;
		if (QC[cp]) break;
		if (cls == 0) starter = pos;
		cls0 = cls;
	}
	return starter;
}

/*
const char* next_invalid_char(const char* src, const Trie::NormalizationForm& nf) const {
	int last_canonical_class = 0;
	const char* cur = Util::nearest_utf8_char_start_point(src);
	const char* starter = cur;
	
	for(; *cur != '\0'; cur = Util::nearest_utf8_char_start_point(cur+1)) {
  int canonical_class = ccc.get_class(cur);
  if(last_canonical_class > canonical_class && canonical_class != 0)
	return starter;

  if(nf.quick_check(cur)==false)
	return starter;

  if(canonical_class==0)
	starter=cur;

  last_canonical_class = canonical_class;
	}
	return cur;
  }

     const char* next_valid_starter(const char* src, const Trie::NormalizationForm& nf) const {
      const char* cur = Util::nearest_utf8_char_start_point(src+1);
      while(ccc.get_class(cur)!=0 || nf.quick_check(cur)==false)
	cur = Util::nearest_utf8_char_start_point(cur+1);
      return cur;
    }
  */
