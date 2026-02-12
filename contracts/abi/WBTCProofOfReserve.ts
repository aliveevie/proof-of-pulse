export const WBTCProofOfReserve = [
	{
		inputs: [{ internalType: 'address', name: 'forwarder', type: 'address' }],
		stateMutability: 'nonpayable',
		type: 'constructor',
	},
	{
		inputs: [],
		name: 'getLatestReserve',
		outputs: [
			{
				components: [
					{ internalType: 'uint256', name: 'btcReserveSats', type: 'uint256' },
					{ internalType: 'uint256', name: 'wbtcSupplySats', type: 'uint256' },
					{ internalType: 'uint256', name: 'collateralRatioBps', type: 'uint256' },
					{ internalType: 'uint256', name: 'btcUsdPriceCents', type: 'uint256' },
					{ internalType: 'uint256', name: 'chainlinkReserveSats', type: 'uint256' },
					{ internalType: 'uint256', name: 'timestamp', type: 'uint256' },
				],
				internalType: 'struct WBTCProofOfReserve.ReserveData',
				name: '',
				type: 'tuple',
			},
		],
		stateMutability: 'view',
		type: 'function',
	},
	{
		inputs: [],
		name: 'getLatestRisk',
		outputs: [
			{ internalType: 'uint8', name: '', type: 'uint8' },
			{ internalType: 'string', name: '', type: 'string' },
			{ internalType: 'uint256', name: '', type: 'uint256' },
		],
		stateMutability: 'view',
		type: 'function',
	},
	{
		inputs: [],
		name: 'isHealthy',
		outputs: [{ internalType: 'bool', name: '', type: 'bool' }],
		stateMutability: 'view',
		type: 'function',
	},
	{
		inputs: [],
		name: 'getReserveValueUsd',
		outputs: [{ internalType: 'uint256', name: '', type: 'uint256' }],
		stateMutability: 'view',
		type: 'function',
	},
	{
		inputs: [],
		name: 'getReserveHistoryLength',
		outputs: [{ internalType: 'uint256', name: '', type: 'uint256' }],
		stateMutability: 'view',
		type: 'function',
	},
	{
		inputs: [{ internalType: 'uint256', name: 'auditId', type: 'uint256' }],
		name: 'requestAudit',
		outputs: [],
		stateMutability: 'nonpayable',
		type: 'function',
	},
	{
		anonymous: false,
		inputs: [
			{ indexed: true, internalType: 'uint256', name: 'auditId', type: 'uint256' },
		],
		name: 'AuditRequested',
		type: 'event',
	},
	{
		anonymous: false,
		inputs: [
			{ indexed: false, internalType: 'uint256', name: 'btcReserveSats', type: 'uint256' },
			{ indexed: false, internalType: 'uint256', name: 'wbtcSupplySats', type: 'uint256' },
			{ indexed: false, internalType: 'uint256', name: 'collateralRatioBps', type: 'uint256' },
			{ indexed: false, internalType: 'uint256', name: 'timestamp', type: 'uint256' },
		],
		name: 'ReserveUpdated',
		type: 'event',
	},
	{
		anonymous: false,
		inputs: [
			{ indexed: false, internalType: 'uint256', name: 'collateralRatioBps', type: 'uint256' },
			{ indexed: false, internalType: 'uint256', name: 'timestamp', type: 'uint256' },
		],
		name: 'UndercollateralizedAlert',
		type: 'event',
	},
	{
		anonymous: false,
		inputs: [
			{ indexed: false, internalType: 'uint256', name: 'ourReserve', type: 'uint256' },
			{ indexed: false, internalType: 'uint256', name: 'clReserve', type: 'uint256' },
			{ indexed: false, internalType: 'uint256', name: 'timestamp', type: 'uint256' },
		],
		name: 'ChainlinkDivergenceAlert',
		type: 'event',
	},
	{
		anonymous: false,
		inputs: [
			{ indexed: false, internalType: 'uint8', name: 'score', type: 'uint8' },
			{ indexed: false, internalType: 'string', name: 'recommendation', type: 'string' },
			{ indexed: false, internalType: 'uint256', name: 'timestamp', type: 'uint256' },
		],
		name: 'RiskUpdated',
		type: 'event',
	},
] as const
