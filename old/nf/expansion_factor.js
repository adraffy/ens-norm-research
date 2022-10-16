export function bytes_from_utf8(s) {
	if (typeof s !== 'string') throw TypeError('expected string');
	let v = [];
	for (let cp of s) {
		cp = cp.codePointAt(0);
		if (cp < 0x80) {
			v.push(cp);
		} else if (cp < 0x800) {
			v.push(0xC0 | (cp >> 6), 0x80 | (cp & 0x3F));
		} else if (cp < 0x10000) {
			v.push(0xE0 | (cp >> 12), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F));
		} else {
			v.push(0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3F), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F));
		}
	}
	return Uint8Array.from(v);
}

function read_cont(v, pos) {
	let b = v[pos];
	if ((b & 0xC0) != 0x80) throw new Error(`malformed utf8 at ${pos}: expected continuation`);
	return b & 0x3F;
}
export function utf8_from_bytes(v) {
	let cps = [];
	let pos = 0;
	while (pos < v.length) {
		let b = v[pos++];
		if (b < 0x80) {
			cps.push(b);
		} else if (b < 0xE0) {			
			cps.push(((b & 0x1F) << 6) | read_cont(v, pos++));
		} else if (b < 0xF0) {
			cps.push(((b & 0x0F) << 12) | (read_cont(v, pos++) << 6) | read_cont(v, pos++));
		} else {
			cps.push(((b & 0x07) << 18) | (read_cont(v, pos++) << 12) | (read_cont(v, pos++) << 6) | read_cont(v, pos++));
		}
	}
	return String.fromCodePoint(...cps);	
}

for (let cp = 0; cp <= 0x10FFFF; cp++) {
	let s0 = String.fromCodePoint(cp);
	let v0 = bytes_from_utf8(s0);
	let s1 = utf8_from_bytes(v0);
	if (s0 != s1) throw new Error('wtf');
}
console.log('OK');

let tally = {};
for (let cp = 0; cp <= 0x10FFFF; cp++) {
	try {
		let form = String.fromCodePoint(cp);
		let v0 = bytes_from_utf8(form);
		let v1 = bytes_from_utf8(form.normalize('NFD'));	
		//let grow = v1.length - v0.length;
		let key = String(v1.length);
		tally[key] = (tally[key] ?? 0) + 1;
	} catch (err) {
		console.log(cp);
		throw err;
	}
}
console.log(tally);


import {EMOJI} from '@adraffy/ensip-norm';

let tally2 = {};
for (let emoji of EMOJI) {
	let key = bytes_from_utf8(String.fromCodePoint(...emoji)).length;
	tally2[key] = (tally2[key] ?? 0) + 1;
}
console.log(tally2);