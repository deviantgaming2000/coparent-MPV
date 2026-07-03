import crypto from "node:crypto";
import express from "express";
import { MockAIProvider } from "./ai/MockAIProvider.js";
import { OpenAIProvider } from "./ai/OpenAIProvider.js";
import { ZAIProvider } from "./ai/ZAIProvider.js";

const app = express();
const port = Number(process.env.PORT ?? 3000);
const inputLimit = 5000;
const responseCache = null;
const monthlyUsage = new Map();
const provider = makeProvider();

app.use(express.json({ limit: "32kb" }));

app.get("/health", (_req, res) => {
  res.json({ ok: true, provider: process.env.AI_PROVIDER ?? "mock" });
});

app.post("/generate-incident-summary", requireAuth, async (req, res) => {
  try {
    const request = sanitizeRequest(req.body);
    const usage = enforceMonthlyLimit(req.auth);
    const result = await provider.generateIncidentSummary(request);

    res.json({
      ...result,
      cached: false,
      usage: {
        tier: req.auth.tier,
        usedThisMonth: usage.used,
        monthlyLimit: usage.limit
      }
    });
  } catch (error) {
    const status = error.statusCode ?? 500;
    res.status(status).json({
      error: status === 500 ? "AI summary could not be generated." : error.message
    });
  }
});

app.post("/generate-final-documentation-summary", requireAuth, async (req, res) => {
  try {
    const request = sanitizeFinalDocumentationRequest(req.body);
    const usage = enforceMonthlyLimit(req.auth);
    const result = await provider.generateFinalDocumentationSummary(request);

    res.json({
      ...result,
      cached: false,
      usage: {
        tier: req.auth.tier,
        usedThisMonth: usage.used,
        monthlyLimit: usage.limit
      }
    });
  } catch (error) {
    const status = error.statusCode ?? 500;
    res.status(status).json({
      error: status === 500 ? "Final documentation could not be generated." : error.message
    });
  }
});

app.listen(port, () => {
  console.log(`FactTrail backend listening on http://localhost:${port}`);
});

function makeProvider() {
  if (process.env.AI_PROVIDER === "openai" && process.env.OPENAI_API_KEY) {
    return new OpenAIProvider();
  }

  if (process.env.AI_PROVIDER === "zai" && process.env.ZAI_API_KEY) {
    return new ZAIProvider();
  }

  return new MockAIProvider();
}

function requireAuth(req, res, next) {
  const authHeader = req.header("Authorization") ?? "";
  const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7).trim() : "";
  const tier = tierForToken(token);

  if (!token || !tier) {
    return res.status(401).json({ error: "Authentication required." });
  }

  req.auth = { tokenHash: hashString(token), tier };
  next();
}

function tierForToken(token) {
  if (!token) {
    return null;
  }

  if (process.env.AUTH_TOKENS) {
    const tokenMap = JSON.parse(process.env.AUTH_TOKENS);
    return tokenMap[token] === "test" ? "test" : tokenMap[token] === "free" ? "free" : null;
  }

  if (process.env.DEV_AUTH_TOKEN && token === process.env.DEV_AUTH_TOKEN) {
    return "test";
  }

  return null;
}

function sanitizeRequest(body) {
  const request = {
    incidentText: stringValue(body.incidentText),
    currentCategory: stringValue(body.currentCategory),
    peopleInvolved: stringValue(body.peopleInvolved),
    location: stringValue(body.location),
    childInvolved: Boolean(body.childInvolved),
    evidenceNotes: stringValue(body.evidenceNotes),
    existingFollowUpAnswers: Array.isArray(body.existingFollowUpAnswers)
      ? body.existingFollowUpAnswers.map((answer) => ({
          question: stringValue(answer.question),
          answer: stringValue(answer.answer)
        }))
      : []
  };
  const combinedLength = JSON.stringify(request).length;

  if (combinedLength > inputLimit) {
    const error = new Error("Input is too long. Please keep the incident details under 5,000 characters.");
    error.statusCode = 413;
    throw error;
  }

  if (!request.incidentText) {
    const error = new Error("incidentText is required.");
    error.statusCode = 400;
    throw error;
  }

  return request;
}

function sanitizeFinalDocumentationRequest(body) {
  const request = {
    originalNotes: stringValue(body.originalNotes),
    incidentDate: dateValue(body.incidentDate),
    category: stringValue(body.category),
    peopleInvolved: stringValue(body.peopleInvolved),
    location: stringValue(body.location),
    childInvolved: Boolean(body.childInvolved),
    evidenceNotes: stringValue(body.evidenceNotes),
    evidenceTypes: stringArray(body.evidenceTypes),
    patternTags: stringArray(body.patternTags),
    followUpAnswers: Array.isArray(body.followUpAnswers)
      ? body.followUpAnswers.map((answer) => ({
          question: stringValue(answer.question),
          answer: stringValue(answer.answer)
        }))
      : [],
    initialAnalysis: typeof body.initialAnalysis === "object" && body.initialAnalysis !== null
      ? body.initialAnalysis
      : null
  };
  const combinedLength = JSON.stringify(request).length;

  if (combinedLength > inputLimit * 2) {
    const error = new Error("Input is too long. Please shorten the incident details before generating final documentation.");
    error.statusCode = 413;
    throw error;
  }

  if (!request.originalNotes) {
    const error = new Error("originalNotes is required.");
    error.statusCode = 400;
    throw error;
  }

  return request;
}

function enforceMonthlyLimit(auth) {
  const limit = auth.tier === "test" ? 100 : 10;
  const usageKey = `${auth.tokenHash}:${monthKey()}`;
  const used = monthlyUsage.get(usageKey) ?? 0;

  if (used >= limit) {
    const error = new Error("Monthly AI usage limit reached.");
    error.statusCode = 429;
    throw error;
  }

  monthlyUsage.set(usageKey, used + 1);

  return { used: used + 1, limit };
}

function hashRequest(request) {
  return hashString(JSON.stringify(request));
}

function hashString(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function monthKey() {
  return new Date().toISOString().slice(0, 7);
}

function stringValue(value) {
  return typeof value === "string" ? value.trim().slice(0, inputLimit) : "";
}

function dateValue(value) {
  if (typeof value === "string") {
    return value.trim();
  }

  if (typeof value === "number" && Number.isFinite(value)) {
    return new Date(Date.UTC(2001, 0, 1) + value * 1000).toISOString();
  }

  return "";
}

function stringArray(value) {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .filter((item) => typeof item === "string")
    .map((item) => item.trim().slice(0, inputLimit))
    .filter(Boolean);
}
