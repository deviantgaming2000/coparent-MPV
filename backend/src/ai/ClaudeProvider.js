import {
  AIProvider,
  normalizeAIResponse,
  normalizeFinalDocumentationResponse,
  normalizeTimelineAnalysis,
  parseJSONContent
} from "./AIProvider.js";
import {
  finalDocumentationPrompt,
  systemPrompt,
  timelineAnalysisPrompt
} from "./ProviderPrompts.js";

// Anthropic Messages API provider. Uses raw fetch (Node 18+ global) to stay
// consistent with the OpenAI/ZAI providers — no SDK dependency required.
// Enable with AI_PROVIDER=claude and ANTHROPIC_API_KEY set.
export class ClaudeProvider extends AIProvider {
  constructor({
    apiKey = process.env.ANTHROPIC_API_KEY,
    baseURL = process.env.ANTHROPIC_BASE_URL ?? "https://api.anthropic.com/v1",
    model = process.env.ANTHROPIC_MODEL ?? "claude-opus-4-8"
  } = {}) {
    super();
    this.apiKey = apiKey;
    this.baseURL = baseURL.replace(/\/$/, "");
    this.model = model;
  }

  async generateIncidentSummary(request) {
    const content = await this.createMessage({
      system: systemPrompt(),
      user: JSON.stringify(request),
      maxTokens: 1200
    });
    return normalizeAIResponse(parseJSONContent(content));
  }

  async generateFinalDocumentationSummary(request) {
    const content = await this.createMessage({
      system: finalDocumentationPrompt(),
      user: JSON.stringify(request),
      maxTokens: 1400
    });
    return normalizeFinalDocumentationResponse(parseJSONContent(content), request);
  }

  async analyzeTimeline(request) {
    const content = await this.createMessage({
      system: timelineAnalysisPrompt(),
      user: JSON.stringify(request),
      maxTokens: 2000
    });
    return normalizeTimelineAnalysis(parseJSONContent(content));
  }

  async createMessage({ system, user, maxTokens }) {
    if (!this.apiKey) {
      throw new Error("ANTHROPIC_API_KEY is not configured");
    }

    const response = await fetch(`${this.baseURL}/messages`, {
      method: "POST",
      headers: {
        "x-api-key": this.apiKey,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json"
      },
      body: JSON.stringify({
        model: this.model,
        max_tokens: maxTokens,
        system,
        messages: [{ role: "user", content: `${user}\n\nRespond with only the JSON described above.` }]
      })
    });

    if (!response.ok) {
      const errorBody = await response.text();
      throw new Error(`Anthropic request failed with ${response.status}: ${errorBody}`);
    }

    const body = await response.json();
    // content is an array of blocks; concatenate the text blocks.
    const text = Array.isArray(body?.content)
      ? body.content.filter((block) => block?.type === "text").map((block) => block.text).join("")
      : "";

    if (!text) {
      throw new Error("Anthropic response did not include text content");
    }

    return text;
  }
}
