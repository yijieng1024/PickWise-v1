const { ChatGoogleGenerativeAI } = require("@langchain/google-genai");
const { ChatPromptTemplate } = require("@langchain/core/prompts");
const { HumanMessage, AIMessage } = require("@langchain/core/messages");
const { MongoDBAtlasVectorSearch } = require("@langchain/mongodb");
const { GoogleGenerativeAIEmbeddings } = require("@langchain/google-genai");
const Laptop = require("../models/Laptop");
const UserPreference = require("../models/userpreference");
const Conversation = require("../models/Conversation");
const mongoose = require("mongoose");
const { MongoClient } = require("mongodb");
require("dotenv").config();

// ------------------ ENV ------------------
const MONGO_URL = process.env.MONGO_URL || process.env.MONGO_URI;
const MONGO_DB = process.env.MONGO_DB || "test";
if (!MONGO_URL) throw new Error("Missing MONGO_URL");
if (!process.env.GOOGLE_API_KEY) throw new Error("Missing GOOGLE_API_KEY");

// ------------------ MODEL ------------------
const model = new ChatGoogleGenerativeAI({
  model: "gemini-3-flash-preview",
  temperature: 0.7,
  apiKey: process.env.GOOGLE_API_KEY,
});

// ------------------ USER PREFERENCES ------------------
async function getUserPreferences(userId) {
  try {
    const pref = await UserPreference.findOne({ userId });
    return {
      priorityFactors: pref?.priorityFactors || [],
      brandPreferences: pref?.brandPreferences || [],
    };
  } catch (e) {
    console.warn("getUserPreferences error:", e.message);
    return { priorityFactors: [], brandPreferences: [] };
  }
}

// ------------------ PROMPTS (DOUBLE CURLIES = ESCAPED) ------------------
const intentPrompt = ChatPromptTemplate.fromTemplate(`
You are a perfect JSON extractor. Return ONLY this exact JSON structure, no extra text, no markdown:

{{"intent_summary": "short summary", "budget_min": number_or_null, "budget_max": number_or_null, "purpose": "", "brands": [], "must_have": [], "avoid": []}}

History:
{history}

Current message: {query}
`);

const filterPrompt = ChatPromptTemplate.fromTemplate(`
Return ONLY a valid MongoDB filter object as JSON. Examples:
{{"price_rm": {{"$gte": 3000, "$lte": 8000}}}}
or just {{}} if no filter.

History:
{history}

Current message: {query}
Intent JSON: {intent}

Respond with pure JSON only.
`);

const recommendPrompt = ChatPromptTemplate.fromTemplate(`
You are Pico, the friendly laptop advisor for PickWise.

Your goal is to recommend 1-3 laptops based on the user's needs.
Data Provided: {laptops}

**CRITICAL INSTRUCTION FOR LINKS:**
1. If the user is just asking for recommendations, list the laptops with their details (Name, Price, Specs, Score). Do NOT provide purchase links yet.
2. IF (and only if) the user explicitly expresses interest in a SPECIFIC laptop found in the data 
(e.g., "I decided to buy....", "I want to buy the Asus," "Show me the HP details," "Go with the first one"), you MUST append a navigation link for that specific laptop.
3. The link format is: **[View Details: Product Name](app://laptop/ID)**
4. Use the 'id' field from the laptop data to fill the ID section.

History:
{history}

User: {query}
Intent: {intent}

Response (Be casual but professional):
`);

// ------------------ CHAINS (OLD STYLE – WORKS EVERYWHERE) ------------------
const intentChain   = intentPrompt.pipe(model);
const filterChain   = filterPrompt.pipe(model);
const recommendChain = recommendPrompt.pipe(model);

// ------------------ SUPER-ROBUST JSON PARSER ------------------
function extractJson(text) {
  if (!text) return {};
  const cleaned = text
    .replace(/```json/g, "")
    .replace(/```/g, "")
    .trim();

  // Find the first { ... } block
  const start = cleaned.indexOf("{");
  const end   = cleaned.lastIndexOf("}");
  if (start === -1 || end === -1) return {};

  const jsonStr = cleaned.slice(start, end + 1);
  try {
    return JSON.parse(jsonStr);
  } catch (e) {
    console.warn("JSON parse failed:", jsonStr);
    return {};
  }
}

// ------------------ HELPERS ------------------
function safeLLMText(resp) {
  if (typeof resp === "string") return resp;
  if (resp?.content) {
    const c = resp.content;
    return Array.isArray(c) ? c.map(i => i?.text || "").join("") : c;
  }
  return "";
}

function safeParseJson(str) {
  if (!str) return {};
  const cleaned = str.replace(/```json/gi, "").replace(/```/g, "").trim();
  const match = cleaned.match(/\{[\s\S]*\}/);
  if (!match) return {};
  try { return JSON.parse(match[0]); } catch { return {}; }
}

// ------------------ RETRIEVAL ------------------
async function hybridRetrieval(userQuery, filter, intentJson) {
  // Brand fallback (keep this — it's gold)
  if (userQuery.match(/hp|h\.p\.|hewlett/i)) filter.brand = { $regex: /^hp$/i };
  if (userQuery.match(/apple|macbook|mac/i)) filter.brand = "Apple";

  // Apply budget & purpose
  const finalFilter = { ...filter };
  if (intentJson.budget_min) finalFilter.price_rm = { ...finalFilter.price_rm, $gte: intentJson.budget_min };
  if (intentJson.budget_max) finalFilter.price_rm = { ...finalFilter.price_rm, $lte: intentJson.budget_max };
  if (intentJson.purpose?.toLowerCase().includes("gaming")) {
    finalFilter.gpu_benchmark = { $gte: 8000 };
  }

  let results = await Laptop.find(finalFilter).limit(30).lean();

  // Fallback if nothing found
  if (!results.length) {
    results = await Laptop.find({
      price_rm: { $gte: 3000, $lte: 8000 }
    }).limit(20).lean();
  }

  return results;
}

// ------------------ MAIN ------------------
async function queryLaptopLLM(userId, userQuery, conversationId) {
  try {
    // History - Securely load only if conversation belongs to current user
    let historyMessages = [];
    let historyStr = "";

    if (conversationId && mongoose.Types.ObjectId.isValid(conversationId)) {
      try {
        const conv = await Conversation.findOne({
          _id: conversationId,
          userId: userId   // This ensures only the owner's conversation is loaded
        }).select("messages").lean(); // .lean() for performance

        if (conv) {
          historyMessages = (conv.messages || []).map(m =>
            m.role === "user" 
              ? new HumanMessage(m.content) 
              : new AIMessage(m.content)
          );

          historyStr = historyMessages
            .map(m => `${m._role === "human" ? "User" : "Assistant"}: ${m.content}`)
            .join("\n");
        }
        // If conv is null → wrong user or deleted → just use empty history (safe)
      } catch (err) {
        console.warn("Failed to load conversation history:", err.message);
        // Silently fail → don't break recommendation if history can't load
      }
    }

        // 1. Intent
    let intentJson = { intent_summary: userQuery, budget_min: null, budget_max: null, purpose: "", brands: [], must_have: [], avoid: [] };
    try {
      const resp = await intentChain.invoke({ history: historyStr, query: userQuery });
      const text = resp?.content || resp?.text || String(resp);
      intentJson = { ...intentJson, ...extractJson(text) };
    } catch (e) {
      console.warn("Intent chain failed:", e.message);
    }

    // 2. Filter
    let filter = {};
    try {
      const resp = await filterChain.invoke({ 
        history: historyStr, 
        query: userQuery, 
        intent: JSON.stringify(intentJson) 
      });
      const text = resp?.content || resp?.text || String(resp);
      filter = extractJson(text);
    } catch (e) {
      console.warn("Filter chain failed:", e.message);
    }

    // 3. Retrieve
    let laptops = await hybridRetrieval(userQuery, filter, intentJson);
    if (!laptops.length) return "No laptops found in your budget.";

    // 4. PICK SCORE ON FILTERED LAPTOPS ONLY
    const { priorityFactors, brandPreferences } = await getUserPreferences(userId);
    const { calculatePickScore } = require("../utils/PickScoreEngine");

    const scored = await Promise.all(
      laptops.map(async l => {
        const score = await calculatePickScore(l, priorityFactors, brandPreferences);
        return { ...l, pick_score: score};
      })
    );
  
    scored.sort((a, b) => b.pick_score - a.pick_score);
    const top = scored.slice(0, 3);

    const laptopInfo = top.map(l => ({
      id: l._id.toString(),
      name: l.product_name,
      brand: l.brand,
      price: `RM ${l.price_rm}`,
      cpu: l.processor_name,
      gpu: l.gpu_model,
      ram: `${l.ram_gb} GB`,
      display: `${l.display_size_inch}" ${l.display_resolution}`,
      pick_score: `Pick Score: ${l.pick_score}/100`,
    }));

    // 5. Recommend
    let responseText = "Here are the best matches:";
    try {
      const res = await recommendChain.invoke({
        history: historyStr,
        query: userQuery,
        intent: JSON.stringify(intentJson),
        laptops: JSON.stringify(laptopInfo, null, 2),
      });
      responseText = safeLLMText(res);
    } catch (e) {
      console.warn("Recommend failed:", e.message);
      responseText += "\n\n" + laptopInfo.map(l => `- ${l.brand} ${l.name}: ${l.price} (${l.pick_score})`).join("\n");
    }

    // Save
    try {
      if (conversationId && mongoose.Types.ObjectId.isValid(conversationId)) {
        await Conversation.updateOne(
          { _id: conversationId },
          {
            $push: {
              messages: {
                $each: [
                  { role: "user", content: userQuery, timestamp: new Date() },
                  { role: "assistant", content: responseText, timestamp: new Date() },
                ],
              },
            },
            $set: { updatedAt: new Date() },
          },
          { upsert: true }
        );
      }
    } catch (e) { console.warn("Save error:", e.message); }

    return responseText.trim();
  } catch (err) {
    console.error("queryLaptopLLM error:", err);
    return "Sorry, something went wrong. Please try again.";
  }
}

// ------------------ EXPORTS ------------------
module.exports = {
  queryLaptopLLM,
};