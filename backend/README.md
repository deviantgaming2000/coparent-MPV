# FactTrail Backend

Backend endpoint for AI-assisted incident summaries. The iOS app calls this service only; provider API keys stay on the backend.

## Local Mock Run

```sh
npm install
npm run dev
```

Then call:

```sh
curl -X POST http://localhost:3000/generate-incident-summary \
  -H "Authorization: Bearer dev-token" \
  -H "Content-Type: application/json" \
  -d '{"incidentText":"Pickup was 30 minutes late and I have text messages.","currentCategory":"Exchange","peopleInvolved":"","location":"","childInvolved":true,"evidenceNotes":"Text screenshots","existingFollowUpAnswers":[]}'
```

## Z.ai Run

```sh
export AI_PROVIDER=zai
export DEV_AUTH_TOKEN=dev-token
export ZAI_API_KEY=your-zai-key
export ZAI_BASE_URL=https://api.z.ai/api/paas/v4
export ZAI_MODEL=glm-5.2
npm start
```

Z.ai uses Bearer auth and OpenAI-compatible chat completions at the configured base URL.

## OpenAI Run

```sh
export AI_PROVIDER=openai
export DEV_AUTH_TOKEN=dev-token
export OPENAI_API_KEY=your-openai-key
export OPENAI_BASE_URL=https://api.openai.com/v1
export OPENAI_MODEL=gpt-5.5
npm start
```

OpenAI uses the Responses API. The iOS app still calls only this backend at `AI_BACKEND_URL`; never put `OPENAI_API_KEY` in the iOS app or `Info.plist`.

## Auth And Tiers

For local development, `DEV_AUTH_TOKEN` maps to the `test` tier.

For multiple tokens, set:

```sh
export AUTH_TOKENS='{"free-user-token":"free","test-user-token":"test"}'
```

Limits are enforced in memory:

- Free tier: 10 AI calls/month
- Test/dev tier: 100 AI calls/month

Response caching is currently disabled during AI workflow development so each request performs a fresh analysis.
