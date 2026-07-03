import {
  AIProvider,
  normalizeAIResponse,
  normalizeFinalDocumentationResponse,
  parseJSONContent
} from "./AIProvider.js";
import { finalDocumentationPrompt, systemPrompt } from "./ProviderPrompts.js";

export class ZAIProvider extends AIProvider {
  constructor({
    apiKey = process.env.ZAI_API_KEY,
    baseURL = process.env.ZAI_BASE_URL ?? "https://api.z.ai/api/paas/v4",
    model = process.env.ZAI_MODEL ?? "glm-5.2"
  } = {}) {
    super();
    this.apiKey = apiKey;
    this.baseURL = baseURL.replace(/\/$/, "");
    this.model = model;
  }

  async generateIncidentSummary(request) {
    if (!this.apiKey) {
      throw new Error("ZAI_API_KEY is not configured");
    }

    const response = await fetch(`${this.baseURL}/chat/completions`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${this.apiKey}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        model: this.model,
        temperature: 0.2,
        max_tokens: 1000,
        response_format: { type: "json_object" },
        messages: [
          {
            role: "system",
            content: systemPrompt()
          },
          {
            role: "user",
            content: JSON.stringify(request)
          }
        ]
      })
    });

    if (!response.ok) {
      const errorBody = await response.text();
      throw new Error(`Z.ai request failed with ${response.status}: ${errorBody}`);
    }

    const body = await response.json();
    const content = body?.choices?.[0]?.message?.content;

    if (typeof content !== "string") {
      throw new Error("Z.ai response did not include message content");
    }

    return normalizeAIResponse(parseJSONContent(content));
  }

  async generateFinalDocumentationSummary(request) {
    if (!this.apiKey) {
      throw new Error("ZAI_API_KEY is not configured");
    }

    const response = await fetch(`${this.baseURL}/chat/completions`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${this.apiKey}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        model: this.model,
        temperature: 0.2,
        max_tokens: 1200,
        response_format: { type: "json_object" },
        messages: [
          {
            role: "system",
            content: finalDocumentationPrompt()
          },
          {
            role: "user",
            content: JSON.stringify(request)
          }
        ]
      })
    });

    if (!response.ok) {
      const errorBody = await response.text();
      throw new Error(`Z.ai final documentation request failed with ${response.status}: ${errorBody}`);
    }

    const body = await response.json();
    const content = body?.choices?.[0]?.message?.content;

    if (typeof content !== "string") {
      throw new Error("Z.ai final documentation response did not include message content");
    }

    return normalizeFinalDocumentationResponse(parseJSONContent(content), request);
  }
}
