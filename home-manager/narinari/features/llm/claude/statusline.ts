#!/usr/bin/env -S deno run --allow-read --allow-env

// Constants
const COMPACTION_THRESHOLD = 200000 // opus 4.5
const BRAILLE = " ⣀⣄⣤⣦⣶⣷⣿"
const DIM = "\x1b[2m"
const RESET = "\x1b[0m"

// Gradient color: green -> yellow -> red
function gradient(pct: number): string {
  if (pct < 50) {
    const r = Math.round(pct * 5.1)
    return `\x1b[38;2;${r};200;80m`
  } else {
    const g = Math.max(0, Math.round(200 - (pct - 50) * 4))
    return `\x1b[38;2;255;${g};60m`
  }
}

// Braille progress bar
function brailleBar(pct: number, width = 8): string {
  pct = Math.min(Math.max(pct, 0), 100)
  const level = pct / 100
  let bar = ""
  for (let i = 0; i < width; i++) {
    const segStart = i / width
    const segEnd = (i + 1) / width
    if (level >= segEnd) {
      bar += BRAILLE[7]
    } else if (level <= segStart) {
      bar += BRAILLE[0]
    } else {
      const frac = (level - segStart) / (segEnd - segStart)
      bar += BRAILLE[Math.min(Math.floor(frac * 7), 7)]
    }
  }
  return bar
}

function fmt(label: string, pct: number): string {
  const p = Math.round(pct)
  return `${DIM}${label}${RESET} ${gradient(pct)}${brailleBar(pct)}${RESET} ${p}%`
}

// Function to calculate tokens from transcript
async function calculateTokensFromTranscript(filePath: string): Promise<number> {
  try {
    const content = await Deno.readTextFile(filePath)
    const lines = content.trim().split("\n")

    let lastUsage = null

    for (const line of lines) {
      try {
        const entry = JSON.parse(line)

        if (entry.type === "assistant" && entry.message?.usage) {
          lastUsage = entry.message.usage
        }
      } catch {
        // Skip invalid JSON lines
      }
    }

    if (lastUsage) {
      const totalTokens =
        (lastUsage.input_tokens || 0) +
        (lastUsage.output_tokens || 0) +
        (lastUsage.cache_creation_input_tokens || 0) +
        (lastUsage.cache_read_input_tokens || 0)
      return totalTokens
    }

    return 0
  } catch {
    return 0
  }
}

// Read JSON input from stdin
const decoder = new TextDecoder()
const input = decoder.decode(
  await Deno.stdin.readable
    .getReader()
    .read()
    .then((r) => r.value),
)
const data = JSON.parse(input)

// Extract values
const sessionId = data.session_id
const transcriptPath = data.transcript_path

// Determine context window percentage
let ctxPct: number | null = null

if (data.context_window?.used_percentage != null) {
  ctxPct = data.context_window.used_percentage
} else {
  // Fallback: calculate from transcript
  let totalTokens = 0

  if (transcriptPath) {
    try {
      const stat = await Deno.stat(transcriptPath)
      if (stat.isFile) {
        totalTokens = await calculateTokensFromTranscript(transcriptPath)
      }
    } catch {
      // Transcript file doesn't exist or can't be read
    }
  } else if (sessionId) {
    const projectsDir = `${Deno.env.get("HOME")}/.claude/projects`

    try {
      for await (const entry of Deno.readDir(projectsDir)) {
        if (entry.isDirectory) {
          const transcriptFile = `${projectsDir}/${entry.name}/${sessionId}.jsonl`

          try {
            const stat = await Deno.stat(transcriptFile)
            if (stat.isFile) {
              totalTokens = await calculateTokensFromTranscript(transcriptFile)
              break
            }
          } catch {
            // File doesn't exist in this project, continue
          }
        }
      }
    } catch {
      // Projects directory doesn't exist or other error
    }
  }

  if (totalTokens > 0) {
    ctxPct = Math.min(100, (totalTokens / COMPACTION_THRESHOLD) * 100)
  }
}

// Rate limit percentages (if available)
const fivePct: number | null = data.rate_limits?.five_hour?.used_percentage ?? null
const weekPct: number | null = data.rate_limits?.seven_day?.used_percentage ?? null

// Build output parts
const parts: string[] = []
if (ctxPct !== null) parts.push(fmt("ctx", ctxPct))
if (fivePct !== null) parts.push(fmt("5h", fivePct))
if (weekPct !== null) parts.push(fmt("7d", weekPct))

if (parts.length > 0) {
  console.log(parts.join(` ${DIM}│${RESET} `))
} else {
  console.log(`${fmt("ctx", 0)}`)
}
