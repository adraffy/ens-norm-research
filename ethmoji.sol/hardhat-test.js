// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");
const fs = require('fs');

async function main() {

	const C = await hre.ethers.getContractFactory("Ethmoji");
	const c = await C.deploy();
	await c.deployed();
	console.log('deployed');
	let buf = fs.readFileSync('./scripts/payload.txt');
	console.log(buf.length);
	await c.uploadEmoji(fs.readFileSync('./scripts/payload.txt', {encoding: 'utf8'}));
	await run_tests(c, true, './scripts/test-pass-min.json');
	await run_tests(c, true, './scripts/test-pass-rng.json');
	await run_tests(c, false, './scripts/test-fail.json');
}

async function run_tests(c, expect, file) {
	let names = JSON.parse(fs.readFileSync(file));
	console.log(`Test ${file} (${names.length}) as ${expect}`);
	for (let name of names) {
		let state = true;
		try {
			await c.callStatic.test(name);
		} catch (err) {
			state = false;
		}
		if (state !== expect) {
			console.log({name, state, expect});
			throw new Error('wtf');
		}
		console.log(name);
	}
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
	console.error(error);
	process.exitCode = 1;
});
