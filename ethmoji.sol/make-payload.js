
import {readFileSync, writeFileSync} from 'node:fs';
import {ens_emoji} from '../ens-normalize.js/src/lib.js';

const EMOJI = ens_emoji();

class Node {
	constructor() {
		this.branches = {};
	}
	get nodes() {
		return Object.values(this.branches).reduce((a, x) => a + 1 + x.nodes, 0);
	}
	add(cp) {
		if (cp == 0xFE0F) {
			this.fe0f = true;
			return this;
		}
		let node = this.branches[cp];
		if (!node) this.branches[cp] = node = new Node();
		return node;
	}
	scan(fn, path = []) {
		fn(this, path);
		for (let [k, node] of Object.entries(this.branches)) {
			node.scan(fn, [...path, [k, node]]);
		}
	}
	collapse_nodes(memo = {}) {
		for (let [k, node] of Object.entries(this.branches)) {
			node.collapse_nodes(memo);
			let key = JSON.stringify(node);
			let dup = memo[key];
			if (dup) {
				this.branches[k] = dup;
			} else {
				memo[key] = node;
			}
		}
	}
	collapse_keys() {
		let m = Object.entries(this.branches);
		let u = this.branches = {};
		while (m.length) {
			let [key, node] = m.pop();
			u[[...m.filter(kv => kv[1] === node).map(kv => kv[0]), key].sort().join()] = node;
			m = m.filter(kv => kv[1] !== node);
			node.collapse_keys();
		}
	}
}

// insert every emoji sequence
let root = new Node();
for (let cps of EMOJI) {
	let node = root;
	for (let cp of cps) {
		node = node.add(cp);
	}
	node.valid = true;
}

// there are sequences of the form:
// a__ MOD b__ MOD2 c__
// where MOD != MOD2 (5x4 = 20 combinations)
// if we remember the first mod, 
// we can pretend the second mod is non-exclusionary (5x5)
// which allows further compression 
// (12193 to 11079 bytes -> saves 1KB, ~10%)
let modifier_set = new Set(['127995', '127996', '127997', '127998', '127999']); // 1F3FB..1F3FF
root.scan((node, path) => {
	// find nodes that are missing 1 modifier
	let v = Object.keys(node.branches);
	if (v.length != modifier_set.size - 1) return; // missing 1
	if (!v.every(k => modifier_set.has(k))) return; // all mods
	// where another modifier already exists in the path
	let m = path.filter(kv => modifier_set.has(kv[0]));
	if (m.length == 0) return;
	let parent = m[m.length - 1][1]; // find closest
	// complete the map so we can collapse
	for (let cp of modifier_set) {
		if (!node.branches[cp]) {
			node.branches[cp] = node.branches[v[0]]; // fake branch
			break;
		}
	}
	// set save on the first modifier
	parent.save_mod = true;
	// set check on the second modifiers
	for (let b of Object.values(node.branches)) {
		b.check_mod = true;
	}
});

// check every emoji sequence for non-standard FE0F handling
for (let cps0 of EMOJI) {
	let node = root;
	let i = 0;
	let n = 0;
	let quirk;
	while (i < cps0.length) {
		let cp = cps0[i++];
		node = node.branches[cp];
		if (i < cps0.length && node.fe0f) {
			if (cps0[i] == 0xFE0F) {
				i++;
			} else {
				if (n != 0) throw new Error('expected first FE0F');
				if (i != 1) throw new Error('expected second character');
				quirk = true;
				//bits |= 1 << index;
			}
			n++;
		}
	}
	node.quirk = quirk;
}

// compress
console.log(`Before: ${root.nodes}`);
root.collapse_nodes();
root.collapse_keys();
console.log(`After: ${root.nodes}`);

let states = 0;
let rules = [];
collect_states(root, 0);
console.log(`States: ${states}`);

function collect_states(node, state0) {
	for (let [keys, x] of Object.entries(node.branches)) {
		let state1 = ++states; 
		for (let key of keys.split(',')) {
			let cp = parseInt(key);
			rules.push({cp, state0, state1, ...x});
		}
		collect_states(x, state1);
	}
}

// this matches logic in Ethmoji.sol
const STATE_BITS = 11; // 0x07FF = (1)
const MAX_STATE = (1 << STATE_BITS) - 1;
if (states > MAX_STATE) throw new Error('wtf state');

function print_hex(name, i) {
	console.log(`${name} 0x${i.toString(16).padStart(4, '0').toUpperCase()}`);
}

const STATE_QUIRK = 0x0800;
const STATE_VALID = 0x1000;
const STATE_SAVE = 0x2000;
const STATE_CHECK = 0x4000;
const STATE_FE0F = 0x8000;

print_hex(' Mask', MAX_STATE);
print_hex('Quirk', STATE_QUIRK);
print_hex('Valid', STATE_VALID);
print_hex(' Save', STATE_SAVE);
print_hex('Check', STATE_CHECK);
print_hex(' FE0F', STATE_FE0F);

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
		if (b.fe0f) state |= STATE_FE0F;
		if (b.check_mod) state |= STATE_CHECK;
		if (b.save_mod) state |= STATE_SAVE;
		if (b.valid) state |= STATE_VALID;
		if (b.quirk) state |= STATE_QUIRK;
		dv.setUint16((0xF - (b.cp & 0xF)) << 1, state);
	}
	dv.setUint32(32, parseInt(key));
	return v; 
});

writeFileSync(new URL('./payload.txt', import.meta.url), '0x' + Buffer.concat(cells).toString('hex'));
