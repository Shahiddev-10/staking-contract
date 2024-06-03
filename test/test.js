const { ethers } = require("ethers");
const tokenBuild = require("../build/contracts/AquamarineToken.json");
const IUniswapV2Router02Build = require("../build/contracts/IUniswapV2Router02.json");

async function main() {
	const provider = new ethers.JsonRpcProvider("http://127.0.0.1:8545");
	const ownerWallet = new ethers.Wallet(
		"0xf6f2007ade9d43bb6df300385948216dd88d00df90aefbc8ed4fb2614c57216a",
		provider
	);

	const user1Wallet = new ethers.Wallet(
		"0x5745dd7be675166a2f7f8b6eaec4bc6cbc88b685ed3443d8e3570f202c7dbe48",
		provider
	);
	const UniswapV2Router02 = new ethers.Contract(
		"0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24",
		IUniswapV2Router02Build.abi,
		ownerWallet
	);

	const tokenContractFactory = new ethers.ContractFactory(
		aquamarineTokenBuild.abi,
		aquamarineTokenBuild.bytecode,
		ownerWallet
	);

	const tokenContract = await tokenContractFactory.deploy();
	await tokenContract.deploymentTransaction().wait();
	const aquamarineTokenAddress = await tokenContract.getAddress();
	console.log("Aquamarine Token Address: ", aquamarineTokenAddress);
	console.log("token: ", await tokenContract.name());
	console.log("token: ", await tokenContract.symbol());
	const WETHAddress = await UniswapV2Router02.WETH();
	const deadAddress = "0x000000000000000000000000000000000000dEaD";
	// 5000000 addind 5 million token and 2 ETH to liquidity

	await (
		await tokenContract.approve(
			await UniswapV2Router02.getAddress(),
			ethers.parseEther("16000000")
		)
	).wait();

	const addLiquidityTxRes = await (
		await UniswapV2Router02.addLiquidityETH(
			aquamarineTokenAddress,
			ethers.parseEther("16000000"),
			0,
			0,
			ownerWallet.address,
			new Date().getTime() + 10000,
			{ value: ethers.parseEther("2") }
		)
	).wait();
	console.log("addLiquidity tx status:", addLiquidityTxRes.status);

	await (await tokenContract.openTrading()).wait();
	for (var i = 0; i < 100; i++) {
		console.log(
			"//////////////////////////////// BUY TEST /////////////////////////////"
		);
		console.log(
			"user balance before swap: ",
			await tokenContract.balanceOf(user1Wallet.address)
		);
		console.log(
			"token balance before swap: ",
			await tokenContract.balanceOf(deadAddress)
		);

		await (
			await UniswapV2Router02.connect(
				user1Wallet
			).swapExactETHForTokensSupportingFeeOnTransferTokens(
				0,
				[WETHAddress, aquamarineTokenAddress],
				user1Wallet.address,
				17140235850000,
				{ value: ethers.parseEther("1") }
			)
		).wait();

		console.log(
			"user balance after swap: ",
			await tokenContract.balanceOf(user1Wallet.address)
		);
		console.log(
			"token balance after swap: ",
			await tokenContract.balanceOf(deadAddress)
		);
	}
}

main();
