import {
	bytesToHex,
	ConsensusAggregationByFields,
	type CronPayload,
	handler,
	CronCapability,
	EVMClient,
	HTTPClient,
	HTTPCapability,
	type EVMLog,
	type HTTPPayload,
	encodeCallMsg,
	getNetwork,
	type HTTPSendRequester,
	hexToBase64,
	LAST_FINALIZED_BLOCK_NUMBER,
	median,
	Runner,
	type Runtime,
	TxStatus,
} from '@chainlink/cre-sdk'
import {
	type Address,
	type Hex,
	decodeFunctionResult,
	encodeFunctionData,
	encodeAbiParameters,
	parseAbiParameters,
	concat,
	keccak256,
	toBytes,
	zeroAddress,
} from 'viem'
import { z } from 'zod'
import { IERC20, AggregatorV3, WBTCProofOfReserve } from '../contracts/abi'
import { askGemini } from './gemini'

// ================================================================
// Config
// ================================================================

const configSchema = z.object({
	cronSchedule: z.string(),
	geminiModel: z.string(),
	geminiApiUrl: z.string(),
	blockstreamApiUrl: z.string(),
	coingeckoApiUrl: z.string(),
	wbtcAddress: z.string(),
	chainlinkBtcReserveFeed: z.string(),
	btcCustodyAddresses: z.array(z.string()),
	mainnetChainSelectorName: z.string(),
	sepoliaChainSelectorName: z.string(),
	porContractAddress: z.string(),
	gasLimit: z.string(),
	geminiApiKey: z.string(),
})

type Config = z.infer<typeof configSchema>

// ================================================================
// HTTP data fetching (runs with DON consensus)
// ================================================================

interface HttpData {
	btcReserveSats: number
	btcUsdPriceCents: number
}

const fetchHttpData = (sendRequester: HTTPSendRequester, config: Config): HttpData => {
	let totalSats = 0

	for (const addr of config.btcCustodyAddresses) {
		const resp = sendRequester
			.sendRequest({ method: 'GET', url: `${config.blockstreamApiUrl}/address/${addr}` })
			.result()

		if (resp.statusCode !== 200) {
			throw new Error(`Blockstream request failed for ${addr}: ${resp.statusCode}`)
		}

		const data = JSON.parse(Buffer.from(resp.body).toString('utf-8'))
		const funded = data.chain_stats.funded_txo_sum as number
		const spent = data.chain_stats.spent_txo_sum as number
		totalSats += funded - spent
	}

	const priceResp = sendRequester
		.sendRequest({
			method: 'GET',
			url: `${config.coingeckoApiUrl}?ids=bitcoin&vs_currencies=usd`,
		})
		.result()

	if (priceResp.statusCode !== 200) {
		throw new Error(`CoinGecko request failed: ${priceResp.statusCode}`)
	}

	const priceData = JSON.parse(Buffer.from(priceResp.body).toString('utf-8'))
	const btcUsdPriceCents = Math.round(priceData.bitcoin.usd * 100)

	return { btcReserveSats: totalSats, btcUsdPriceCents }
}

// ================================================================
// EVM reads (mainnet)
// ================================================================

const readWbtcTotalSupply = (runtime: Runtime<Config>): bigint => {
	const network = getNetwork({
		chainFamily: 'evm',
		chainSelectorName: runtime.config.mainnetChainSelectorName,
		isTestnet: false,
	})

	if (!network) {
		throw new Error('Mainnet network not found')
	}

	const evmClient = new EVMClient(network.chainSelector.selector)
	const callData = encodeFunctionData({ abi: IERC20, functionName: 'totalSupply' })

	const result = evmClient
		.callContract(runtime, {
			call: encodeCallMsg({
				from: zeroAddress,
				to: runtime.config.wbtcAddress as Address,
				data: callData,
			}),
			blockNumber: LAST_FINALIZED_BLOCK_NUMBER,
		})
		.result()

	return decodeFunctionResult({
		abi: IERC20,
		functionName: 'totalSupply',
		data: bytesToHex(result.data),
	})
}

const readChainlinkReserve = (runtime: Runtime<Config>): bigint => {
	const network = getNetwork({
		chainFamily: 'evm',
		chainSelectorName: runtime.config.mainnetChainSelectorName,
		isTestnet: false,
	})

	if (!network) {
		throw new Error('Mainnet network not found')
	}

	const evmClient = new EVMClient(network.chainSelector.selector)
	const callData = encodeFunctionData({ abi: AggregatorV3, functionName: 'latestRoundData' })

	const result = evmClient
		.callContract(runtime, {
			call: encodeCallMsg({
				from: zeroAddress,
				to: runtime.config.chainlinkBtcReserveFeed as Address,
				data: callData,
			}),
			blockNumber: LAST_FINALIZED_BLOCK_NUMBER,
		})
		.result()

	const decoded = decodeFunctionResult({
		abi: AggregatorV3,
		functionName: 'latestRoundData',
		data: bytesToHex(result.data),
	})

	const answer = decoded[1]
	return answer >= 0n ? answer : 0n
}

// ================================================================
// Report encoding
// ================================================================

const encodeReserveReport = (data: {
	btcReserveSats: bigint
	wbtcSupplySats: bigint
	collateralRatioBps: bigint
	btcUsdPriceCents: bigint
	chainlinkReserveSats: bigint
	timestamp: bigint
}): Hex => {
	const encoded = encodeAbiParameters(
		parseAbiParameters('uint256, uint256, uint256, uint256, uint256, uint256'),
		[
			data.btcReserveSats,
			data.wbtcSupplySats,
			data.collateralRatioBps,
			data.btcUsdPriceCents,
			data.chainlinkReserveSats,
			data.timestamp,
		],
	)
	return concat(['0x01', encoded])
}

const encodeRiskReport = (score: number, recommendation: string, timestamp: bigint): Hex => {
	const encoded = encodeAbiParameters(parseAbiParameters('uint8, string, uint256'), [
		score,
		recommendation,
		timestamp,
	])
	return concat(['0x02', encoded])
}

// ================================================================
// Write report to Sepolia
// ================================================================

const writeReportToSepolia = (runtime: Runtime<Config>, payload: Hex): void => {
	const network = getNetwork({
		chainFamily: 'evm',
		chainSelectorName: runtime.config.sepoliaChainSelectorName,
		isTestnet: true,
	})

	if (!network) {
		throw new Error('Sepolia network not found')
	}

	const evmClient = new EVMClient(network.chainSelector.selector)

	const reportResponse = runtime
		.report({
			encodedPayload: hexToBase64(payload),
			encoderName: 'evm',
			signingAlgo: 'ecdsa',
			hashingAlgo: 'keccak256',
		})
		.result()

	const resp = evmClient
		.writeReport(runtime, {
			receiver: runtime.config.porContractAddress,
			report: reportResponse,
			gasConfig: { gasLimit: runtime.config.gasLimit },
		})
		.result()

	if (resp.txStatus !== TxStatus.SUCCESS) {
		throw new Error(`Failed to write report: ${resp.errorMessage || resp.txStatus}`)
	}

	runtime.log(`Report written: ${bytesToHex(resp.txHash || new Uint8Array(32))}`)
}

// ================================================================
// Core PoR computation
// ================================================================

const computeAndWritePoR = (runtime: Runtime<Config>): string => {
	runtime.log('Fetching BTC reserves and price...')

	const httpClient = new HTTPClient()
	const httpData = httpClient
		.sendRequest(
			runtime,
			fetchHttpData,
			ConsensusAggregationByFields<HttpData>({
				btcReserveSats: median,
				btcUsdPriceCents: median,
			}),
		)(runtime.config)
		.result()

	runtime.log(
		`BTC reserves: ${httpData.btcReserveSats} sats, price: ${httpData.btcUsdPriceCents} cents`,
	)

	const wbtcSupply = readWbtcTotalSupply(runtime)
	runtime.log(`WBTC supply: ${wbtcSupply.toString()}`)

	const chainlinkReserve = readChainlinkReserve(runtime)
	runtime.log(`Chainlink reserve: ${chainlinkReserve.toString()}`)

	const btcReserveSats = BigInt(httpData.btcReserveSats)
	const collateralRatioBps = wbtcSupply > 0n ? (btcReserveSats * 10000n) / wbtcSupply : 0n
	const timestamp = BigInt(Math.floor(runtime.now().getTime() / 1000))

	runtime.log(`Collateral ratio: ${collateralRatioBps.toString()} bps`)

	const payload = encodeReserveReport({
		btcReserveSats,
		wbtcSupplySats: wbtcSupply,
		collateralRatioBps,
		btcUsdPriceCents: BigInt(httpData.btcUsdPriceCents),
		chainlinkReserveSats: chainlinkReserve,
		timestamp,
	})

	writeReportToSepolia(runtime, payload)

	return `PoR updated: ratio=${collateralRatioBps.toString()}bps`
}

// ================================================================
// Handler 1: Cron trigger (hourly PoR update)
// ================================================================

const onCronTrigger = (runtime: Runtime<Config>, payload: CronPayload): string => {
	if (!payload.scheduledExecutionTime) {
		throw new Error('Scheduled execution time is required')
	}

	runtime.log('Running CronTrigger — hourly PoR update')
	return computeAndWritePoR(runtime)
}

// ================================================================
// Handler 2: Log trigger (audit request → Gemini AI risk analysis)
// ================================================================

const onLogTrigger = (runtime: Runtime<Config>, payload: EVMLog): string => {
	runtime.log('Running LogTrigger — audit request')

	const auditId =
		payload.topics.length > 1 ? bytesToHex(payload.topics[1]) : '0x0'
	runtime.log(`Audit ID: ${auditId}`)

	// Fetch fresh BTC reserves + price via HTTP
	const httpClient = new HTTPClient()
	const httpData = httpClient
		.sendRequest(
			runtime,
			fetchHttpData,
			ConsensusAggregationByFields<HttpData>({
				btcReserveSats: median,
				btcUsdPriceCents: median,
			}),
		)(runtime.config)
		.result()

	runtime.log(
		`BTC reserves: ${httpData.btcReserveSats} sats, price: ${httpData.btcUsdPriceCents} cents`,
	)

	// Read WBTC supply + Chainlink reserve from mainnet
	const wbtcSupply = readWbtcTotalSupply(runtime)
	const chainlinkReserve = readChainlinkReserve(runtime)
	const btcReserveSats = BigInt(httpData.btcReserveSats)
	const collateralRatioBps = wbtcSupply > 0n ? (btcReserveSats * 10000n) / wbtcSupply : 0n

	runtime.log(`WBTC supply: ${wbtcSupply.toString()}, ratio: ${collateralRatioBps.toString()} bps`)

	// Build Gemini prompt
	const prompt = `You are a WBTC Proof of Reserve auditor. Analyze the following data and provide a risk assessment.

BTC reserve from Blockstream (sats): ${httpData.btcReserveSats}
WBTC supply on Ethereum (sats): ${wbtcSupply.toString()}
Collateral ratio (bps, 10000=100%): ${collateralRatioBps.toString()}
Chainlink PoR reserve (sats): ${chainlinkReserve.toString()}
BTC price (USD cents): ${httpData.btcUsdPriceCents}

Respond in EXACTLY this format (two lines only):
score: <number 0-100 where 0=safe 100=critical>
recommendation: <one sentence recommendation>`

	const riskResult = askGemini(runtime, runtime.config.geminiApiUrl, runtime.config.geminiApiKey, prompt)
	runtime.log(`Gemini risk: score=${riskResult.score}, rec="${riskResult.recommendation}"`)

	// Encode and write risk report
	const timestamp = BigInt(Math.floor(runtime.now().getTime() / 1000))
	const riskPayload = encodeRiskReport(riskResult.score, riskResult.recommendation, timestamp)
	writeReportToSepolia(runtime, riskPayload)

	return `Audit complete: score=${riskResult.score}`
}

// ================================================================
// Handler 3: HTTP trigger (on-demand PoR update)
// ================================================================

const onHttpTrigger = (runtime: Runtime<Config>, _payload: HTTPPayload): string => {
	runtime.log('Running HTTP trigger — on-demand PoR update')
	return computeAndWritePoR(runtime)
}

// ================================================================
// Workflow initialization
// ================================================================

const initWorkflow = (config: Config) => {
	const cronTrigger = new CronCapability()
	const httpTrigger = new HTTPCapability()

	const sepoliaNetwork = getNetwork({
		chainFamily: 'evm',
		chainSelectorName: config.sepoliaChainSelectorName,
		isTestnet: true,
	})

	if (!sepoliaNetwork) {
		throw new Error('Sepolia network not found')
	}

	const sepoliaClient = new EVMClient(sepoliaNetwork.chainSelector.selector)

	const auditEventSig = keccak256(toBytes('AuditRequested(uint256)'))

	return [
		handler(cronTrigger.trigger({ schedule: config.cronSchedule }), onCronTrigger),
		handler(
			sepoliaClient.logTrigger({
				addresses: [config.porContractAddress],
				topics: [{ values: [auditEventSig] }],
			}),
			onLogTrigger,
		),
		handler(httpTrigger.trigger({}), onHttpTrigger),
	]
}

// ================================================================
// Entry point
// ================================================================

export async function main() {
	const runner = await Runner.newRunner<Config>({ configSchema })
	await runner.run(initWorkflow)
}
