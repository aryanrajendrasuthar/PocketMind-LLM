# Offline Limitations

## What PocketMind Can Answer Offline

PocketMind's knowledge comes from training data with a fixed cutoff date. It excels at tasks that do not require real-time or location-specific information:

| Category | Examples |
|---|---|
| Reasoning & logic | Math problems, logical puzzles, argument analysis |
| Writing & editing | Drafting emails, essays, proofreading, summarization |
| Code | Writing, explaining, debugging code in any language |
| General knowledge | History, science, geography, language (as of training cutoff) |
| Learning & explanation | Explain a concept, teach a skill, compare ideas |
| Creative tasks | Stories, brainstorming, poems, scripts |
| Personal productivity | To-do lists, planning, decision frameworks |

---

## What Requires Live Data

The following categories require information PocketMind cannot have — it was trained on a static dataset with a knowledge cutoff:

| Category | Examples | Why |
|---|---|---|
| Stock & crypto prices | "AAPL price today", "Bitcoin value now" | Changes by the second |
| Weather | "Will it rain tomorrow in Phoenix?" | Requires live forecast data |
| News & current events | "What happened in the election?", "Latest scores" | Post-cutoff events unknown |
| Sports results | "Who won the game last night?" | Real-time data |
| Business info | "Is this restaurant open?", "Store hours for Target" | Changes frequently |
| Directions & transit | "How do I get there from here?" | Requires location + live traffic |
| Product availability | "Is the iPhone 17 in stock?" | Live inventory |
| Anything "right now" | Queries with "today", "right now", "current", "latest" + time-sensitive noun | Requires live data |

---

## How the CapabilityBoundaryClassifier Works

The classifier runs before every inference call. It is a two-stage pipeline:

**Stage 1: Rule-based keyword matching**

Fast, deterministic. Checks for:
- Trigger keywords: `today`, `right now`, `current`, `latest`, `live`, `now`, `tonight`, `this week`, `yesterday`, `forecast`
- Combined with time-sensitive nouns: `price`, `weather`, `news`, `score`, `result`, `election`, `stock`, `crypto`, `traffic`, `hours`, `open`, `rate`

A match at Stage 1 immediately returns `.requiresLiveData` without invoking the ML model.

**Stage 2: CoreML text classifier (< 5 MB)**

For ambiguous queries that pass the keyword filter, a lightweight binary classifier decides between `.fullyOffline` and `.requiresLiveData`. Trained on ~10,000 labeled examples.

---

## User-Facing Language

When the classifier returns `.requiresLiveData`, PocketMind shows a sheet with this language:

> **This question needs live information**
>
> PocketMind works entirely offline — it doesn't have access to the internet or real-time data.
>
> To get an accurate answer for "[user query excerpt]", try:
> - **Safari** for current information
> - **Siri** for quick facts and device integrations
> - **Maps** for directions and business hours
>
> You can still ask PocketMind, but its answer will be based on training data and may be outdated.
>
> [Ask PocketMind anyway]  [Cancel]

The user can always proceed. PocketMind never blocks a query — it informs and then respects the user's choice.
