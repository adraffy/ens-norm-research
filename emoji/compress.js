import {readFile, writeFile} from 'node:fs/promises';
//import {inspect} from 'node:util';

let {
	keycaps, 
	modifier_base,
	modifier,
	style, 
	whitelist_seq, 
	whitelist_zwj
} = JSON.parse(await readFile(new URL('../data/ens-normalize-hr.json', import.meta.url)));

let sequences = [
	keycaps.map(x => [x, 0xFE0F, 0x20E3]),
	style.map(x => [x, 0xFE0F]),
	modifier_base.flatMap(x => modifier.map(y => [x, y])),
	whitelist_seq,
	whitelist_zwj
].flat();

class Node {
	constructor() {
		this.branches = {};
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
	get node_count() {
		return Object.values(this.branches).reduce((a, x) => a + x.node_count, this.end|0);
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
	collect_rules(rules, uneaten, state0, next_state) {
		++uneaten;
		for (let [keys, node] of Object.entries(this.branches)) {
			let state1 = next_state(); 
			for (let key of keys.split(',')) {
				let cp = parseInt(key);
				rules.push({cp,
					state0, state1,
					eat: node.end ? uneaten : 0,
					fe0f: node.fe0f|0,
					check_mod: node.check_mod|0,
					save_mod: node.save_mod|0
				});
			}
			node.collect_rules(rules, node.end ? 0 : uneaten, state1, next_state);
		}
	}
}

let root = new Node();
for (let cps of sequences) {
	let node = root;
	for (let cp of cps) {
		node = node.add(cp);
	}
	node.end = true;
}


// there are sequences of the form:
// a__ MOD b__ MOD2 c__ 
// where MOD != MOD2 (5x4 = 20 combinations)
// if we remember the first mod, 
// we can pretend the second mod is non-exclusionary (5x5)
// which allows further compression
let modifier_set = new Set(modifier.map(x => x.toString()));
root.scan((node, path) => {
	// look nodes that are missing 1 modifier
	let v = Object.keys(node.branches);
	if (v.length != modifier_set.size - 1) return; 
	if (!v.every(k => modifier_set.has(k))) return;
	// where another modifier already exists in the path
	let parent = path.find(kv => modifier_set.has(kv[0]));
	if (parent == node) throw new Error('wtf');
	// mark the first modifier
	parent.save_mod = true;
	// check on the second modifier
	node.check_mod = true;	
	// complete the map so we collapse
	for (let cp of modifier_set) {
		if (!node.branches[cp]) {
			node.add(cp).end = true;
			break;
		}
	}
});

root.collapse_nodes();
root.collapse_keys();
//console.log(inspect(root, {depth: null, colors: true}));

// turn tree into transitions
let rules = [];
let state = 0;
root.collect_rules(rules, 0, state, () => ++state);

await writeFile(new URL('./seqs.json', import.meta.url), JSON.stringify(sequences));
await writeFile(new URL('./tree.json', import.meta.url), JSON.stringify(root));
await writeFile(new URL('./rules.json', import.meta.url), JSON.stringify(rules));

console.log({
	emoji: sequences.length,
	nodes: root.node_count,
	rules: rules.length,	
	states: state
});

// experimental
let key_freq = {};
root.scan(node => {
	for (let key of Object.keys(node.branches)) {
		key_freq[key] = (key_freq[key] ?? 0) + 1;
	}
});
await writeFile(new URL('./key-tally.json', import.meta.url), JSON.stringify(Object.entries(key_freq).sort((a, b) => b[1] - a[1]).map(v => v.reverse())));
