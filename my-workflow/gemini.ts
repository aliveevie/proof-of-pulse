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
						generationConfig: { temperature: 0, maxOutputTokens: 256 },
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
						return {
							score: 50,
							recommendation: `Gemini API returned ${response.statusCode}, using default assessment`,
						}
					}

					const responseText = Buffer.from(response.body).toString('utf-8')
					const parsed = JSON.parse(responseText)
					const content: string = parsed.candidates[0].content.parts[0].text

					const scoreMatch = content.match(/score[:\s]*(\d+)/i)
					const score = scoreMatch ? parseInt(scoreMatch[1]) : 50

					const recMatch = content.match(/recommendation[:\s]*(.*?)(?:\n|$)/i)
					const recommendation = recMatch ? recMatch[1].trim() : content.substring(0, 200)

					return { score, recommendation }
				} catch {
					return {
						score: 50,
						recommendation: 'Gemini API unavailable, using default assessment',
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
