import {readFile, writeFile} from 'node:fs/promises';

function make_chunks(m, max = 8192) {
	let chunk;
	let chunks = [];
	for (let v of m) {
		if (!chunk || chunk.length + v.length > max) {
			chunks.push(chunk = []);
		}
		chunk.push(...v);
	}
	return chunks;
}

function hex_str(v) {
	return '0x' + v.map(x => x.toString(16).padStart(2, '0')).join('');
}

let rules = JSON.parse(await readFile(new URL('./rules.json', import.meta.url)));

const EAT_BITS = 4;
const STATE_BITS = 9;
// 9 + 4 + (3 flags) = 16
// FSC123ab
// (cp bits-4) + state bits
// (24 - 4) + 9 = 29

const MAX_EAT = (1 << EAT_BITS) - 1;
const MAX_STATE = (1 << STATE_BITS) - 1;

let max_eat = rules.reduce((a, x) => Math.max(a, x.eat), 0);
if (max_eat > MAX_EAT) {
	throw new Error('wtf eat');
}

let max_state = rules.reduce((a, x) => Math.max(a, x.state0, x.state1), 0);
if (max_state > MAX_STATE) {
	throw new Error('wtf state');
}

let buckets = {};
for (let rule of rules) {
	let key = String((rule.state0<<20)|(rule.cp>>4));
	let bucket = buckets[key];
	if (!bucket) buckets[key] = bucket = [];
	bucket.push(rule);
}


let cells = Object.entries(buckets).map(([key, bucket]) => {	
	let v = new Uint8Array(36);
	let dv = new DataView(v.buffer);	
	for (let b of bucket) {
		let state = (b.eat << STATE_BITS) | b.state1;
		if (b.fe0f) state |= 0x8000;
		if (b.save_mod) state |= 0x4000;
		if (b.check_mod) state |= 0x2000;
		dv.setUint16((0xF - (b.cp & 0xF)) << 1, state);
	}
	dv.setUint32(32, parseInt(key));
	return v; 
});


//await writeFile(new URL('./payload-matrix.json', import.meta.url), JSON.stringify(cells.map(v => [...v])));

let chunks = make_chunks(cells, 90000);
await writeFile(new URL('./payload-chunks.json', import.meta.url), JSON.stringify(chunks.map(hex_str)));

console.log({
	max_eat, MAX_EAT,
	max_state, MAX_STATE,
	cells: cells.length,
	chunks: chunks.map(v => v.length)
});



/*
function encode_rule(rule) {
	return [
		rule.state0,
		(rule.cp >> 16) & 0xFF,
		(rule.cp >> 8) & 0xFF,
		rule.cp & 0xFF,
		rule.fe0f*0x80 | rule.save_mod*0x40 | rule.check_mod*0x20,
		rule.state1
	];
}

let encoded = rules.map(encode_rule);
if (!encoded.every(v => v.every(x => Number.isSafeInteger(x) && x >= 0 && x < 256))) {
	throw new Error('wtf encoded');
}
await writeFile(new URL('./payload.bin', import.meta.url), Uint8Array.from(encoded.flat()));

let chunks = make_chunks(encoded);

function hex_str(v) {
	return '0x' + v.map(x => x.toString(16).padStart(2, '0')).join('');
}
await writeFile(new URL('./payload.json', import.meta.url), JSON.stringify(chunks.map(hex_str)));
*/
