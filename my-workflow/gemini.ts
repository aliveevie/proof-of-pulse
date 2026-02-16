import {
	HTTPClient,
	type HTTPSendRequester,
	ConsensusAggregationByFields,
	median,
	identical,
	type Runtime,
} from '@chainlink/cre-sdk'

export interface GeminiResponse {
	score: number
	recommendation: string
}

export const askGemini = (
	runtime: Runtime<any>,
	geminiApiUrl: string,
	geminiApiKey: string,
	prompt: string,
): GeminiResponse => {
	const client = new HTTPClient()

	return client
		.sendRequest(
			runtime,
			(sendRequester: HTTPSendRequester, promptText: string): GeminiResponse => {
				try {
					const body = JSON.stringify({
						contents: [{ parts: [{ text: promptText }] }],
						generationConfig: { temperature: 0, maxOutputTokens: 1024 },
					})

					const response = sendRequester
						.sendRequest({
							method: 'POST',
							url: `${geminiApiUrl}?key=${geminiApiKey}`,
							headers: { 'Content-Type': 'application/json' },
							body: Buffer.from(body).toString('base64'),
						})
						.result()

					if (response.statusCode !== 200) {
						runtime.log(`Gemini API error: HTTP ${response.statusCode}`)
						return {
							score: 0,
							recommendation: `[API error ${response.statusCode}] Unable to perform AI risk assessment`,
						}
					}

					const responseText = Buffer.from(response.body).toString('utf-8')
					const parsed = JSON.parse(responseText)

					if (
						!parsed.candidates ||
						!Array.isArray(parsed.candidates) ||
						parsed.candidates.length === 0 ||
						!parsed.candidates[0].content?.parts?.[0]?.text
					) {
						runtime.log('Gemini returned unexpected response structure')
						return {
							score: 0,
							recommendation: '[Parse error] Gemini returned unexpected response format',
						}
					}

					const content: string = parsed.candidates[0].content.parts[0].text

					const scoreMatch = content.match(/score[:\s]*(\d+)/i)
					let score = scoreMatch ? parseInt(scoreMatch[1]) : 0

					// Clamp score to valid range (0 = safe, 100 = critical)
					score = Math.max(0, Math.min(100, score))

					const recMatch = content.match(/recommendation[:\s]*(.*?)(?:\n|$)/i)
					const recommendation = recMatch && recMatch[1].trim().length > 0
						? recMatch[1].trim().substring(0, 256)
						: content.substring(0, 200).trim()

					return { score, recommendation }
				} catch (err) {
					const errMsg = err instanceof Error ? err.message : 'unknown error'
					runtime.log(`Gemini integration error: ${errMsg}`)
					return {
						score: 0,
						recommendation: `[Error] AI risk assessment unavailable: ${errMsg}`,
					}
				}
			},
			ConsensusAggregationByFields<GeminiResponse>({
				score: median,
				recommendation: identical,
			}),
		)(prompt)
		.result()
}
