import {ens_normalize, ens_emoji} from '../ens-normalize.js/src/lib.js';
import {random_sample} from '../ens-normalize.js/src/utils.js';
import {readFileSync, writeFileSync} from 'node:fs';

writeFileSync(new URL('./test-pass-min.json', import.meta.url), JSON.stringify(ens_emoji().map(cps => {
	let norm = ens_normalize(String.fromCodePoint(...cps));
	switch ([...norm].length) {
		case 1:
			norm = norm + norm + norm;
			break;
		case 2:
			norm = norm + norm;
			break;
	}	
	return norm + '.eth';
})));

writeFileSync(new URL('./test-pass-rng.json', import.meta.url), JSON.stringify(ens_emoji().map(cps => {
	let norm = ens_normalize(String.fromCodePoint(...cps));
	norm = Array(3 + Math.random() * 7|0).fill(norm).join('');
	return norm + '.eth';
})));

let tests = JSON.parse(readFileSync(new URL('../ens-normalize.js/validate/tests.json', import.meta.url)));
tests = tests.filter(x => x.error);
tests = tests.map(x => x.name);
tests = tests.map(x => x.endsWith('.eth') ? x : `${x}.eth`);
//tests = random_sample(tests, 1000);
writeFileSync(new URL('./test-fail.json', import.meta.url), JSON.stringify(tests));

