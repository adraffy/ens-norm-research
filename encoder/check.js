import {readFile} from 'node:fs/promises';

function rand(n) {
	return (Math.random() * n)|0;
}

let seqs = JSON.parse(await readFile(new URL('./seqs.json', import.meta.url)));
let rules = JSON.parse(await readFile(new URL('./rules.json', import.meta.url)));

let rules_map = Object.fromEntries(rules.map(x => [(x.state0 << 24) | x.cp, x]));

function parse(cps, pos = 0) {
	let len = 0;
	let state = 0;
	let eat = 0;
	let fe0f = 0;
	let extra = 0;	
	let saved;
	while (pos < cps.length) {
		let cp = cps[pos++];
		if (cp === 0xFE0F) { 
			if (fe0f === 0) break;
			fe0f = 0; 
			if (eat > 0) {
				len++; 
			} else {
				extra++;
			}
		} else {
			let rule = rules_map[(state << 24) | cp];
			if (!rule) break;
			//console.log(rule);
			eat = rule.eat;
			len += eat;
			if (extra > 0 && eat > 0) {
				len += extra;
				extra = 0;
			}
			fe0f = rule.fe0f;
			if (rule.save_mod) {
				saved = cp;
			} else if (rule.check_mod) {
				if (saved === cp) break;
			}
			state = rule.state1;
		}
	}
	return len;
}

// AfBfC => [ABC, AfBC, ABfC, AfBfC]
function gen_fe0f_variants(cps) {
	let a = [cps];
	for (let i = 0; i < cps.length; i++) {
		if (cps[i] === 0xFE0F) {
			a.push(...a.map(v => {
				let u = v.slice();
				u[i] = -1;
				return u;
			}));
		}
	}
	return a.map(v => v.filter(x => x >= 0));
}

// check that every emoji parses correctly
for (let cps0 of seqs) {
	for (let cps of gen_fe0f_variants(cps0)) {
		if (parse(cps) != cps.length) {
			console.log({cps0, cps});
			throw new Error();
		}
	}
}

// randomly mangle emoji
for (let i = 0; i < 1_000_000; i++) {
	let cps = seqs[rand(seqs.length)].slice();
	cps[rand(cps.length)] = 1; // non-emoji cp
	if (parse(cps) === cps.length) {
		console.log({cps});
		throw new Error(`mangled`);
	}
}

// insert extra inner FE0F
for (let cps0 of seqs) {
	for (let i = cps0.length - 2; i >= 0; i--) {
		if (cps0[i] === 0xFE0F) {
			let cps = cps0.slice();
			cps.splice(i, 0, 0xFE0F);
			if (parse(cps) === cps.length) {
				console.log(cps0, cps);
				throw new Error('double fe0f');
			}
		}
	}
}
	