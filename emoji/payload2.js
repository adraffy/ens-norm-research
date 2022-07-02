import {readFile, writeFile} from 'node:fs/promises';

function make_chunks(m, max = Infinity) {
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

const STATE_BITS = 12;
const MAX_STATE = (1 << STATE_BITS) - 1;

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
		let state = b.state1;
		if (b.fe0f) state |= 0x8000;
		if (b.check_mod) state |= 0x4000;
		if (b.save_mod) state |= 0x2000;
        if (b.eat) state |= 0x1000;
		dv.setUint16((0xF - (b.cp & 0xF)) << 1, state);
	}
	dv.setUint32(32, parseInt(key));
	return v; 
});

//await writeFile(new URL('./payload-matrix.json', import.meta.url), JSON.stringify(cells.map(v => [...v])));

let chunks = make_chunks(cells);
await writeFile(new URL('./payload-chunks2.json', import.meta.url), JSON.stringify(chunks.map(hex_str)));

console.log({
	max_state, MAX_STATE,
	cells: cells.length,
	chunks: chunks.map(v => v.length)
});