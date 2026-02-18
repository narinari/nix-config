interface HookData {
  session_id: string
  transcript_path: string
  hook_event_name: "Stop" | "Notification"
  stop_hook_active?: boolean
}

type NotifyMethod = "macos-local" | "linux-local" | "remote-tcp"

function detectNotifyMethod(): NotifyMethod {
  const os = Deno.build.os
  const isRemote = !!Deno.env.get("SSH_CONNECTION")

  if (os === "darwin") {
    return "macos-local"
  } else if (os === "linux" && isRemote) {
    return "remote-tcp"
  } else {
    return "linux-local"
  }
}

interface NotificationContent {
  title: string
  subtitle: string
  body: string
  sound: string
}

async function sendNotification(method: NotifyMethod, content: NotificationContent): Promise<void> {
  switch (method) {
    case "macos-local": {
      const osascriptCmd = `display notification "${content.body}" with title "${content.title}" subtitle "${content.subtitle}" sound name "${content.sound}"`
      const cmd = new Deno.Command("osascript", {
        args: ["-e", osascriptCmd],
        stdout: "piped",
        stderr: "piped",
      })
      await cmd.output()
      break
    }

    case "remote-tcp": {
      const osascriptCmd = `display notification "${content.body}" with title "${content.title}" subtitle "${content.subtitle}" sound name "${content.sound}"`
      const conn = await Deno.connect({
        hostname: "localhost",
        port: 60000,
      })
      await conn.write(new TextEncoder().encode(osascriptCmd + "\n"))
      await conn.closeWrite()
      conn.close()
      break
    }

    case "linux-local": {
      const cmd = new Deno.Command("notify-send", {
        args: [
          "--app-name=Claude Code",
          `${content.title}: ${content.subtitle}`,
          content.body,
        ],
        stdout: "piped",
        stderr: "piped",
      })
      await cmd.output()
      break
    }
  }
}

async function getRepoInfo(): Promise<string> {
  const currentDir = Deno.cwd()

  const gitCheckProcess = new Deno.Command("git", {
    args: ["rev-parse", "--is-inside-work-tree"],
    stdout: "piped",
    stderr: "piped",
  })

  const gitCheckResult = await gitCheckProcess.output()
  const isGitRepo =
    gitCheckResult.success && new TextDecoder().decode(gitCheckResult.stdout).trim() === "true"

  if (!isGitRepo) {
    return currentDir.split("/").pop() || ""
  }

  const remoteProcess = new Deno.Command("git", {
    args: ["remote", "get-url", "origin"],
    stdout: "piped",
    stderr: "piped",
  })

  const remoteResult = await remoteProcess.output()
  const remoteUrl = new TextDecoder().decode(remoteResult.stdout).trim()

  let repoName = ""
  if (remoteUrl && remoteResult.success) {
    const match = remoteUrl.match(/[/:]([^/]+?)(?:\.git)?$/)
    repoName = match ? match[1] : ""
  }

  if (!repoName) {
    repoName = currentDir.split("/").pop() || ""
  }

  const branchProcess = new Deno.Command("git", {
    args: ["branch", "--show-current"],
    stdout: "piped",
    stderr: "piped",
  })

  const branchResult = await branchProcess.output()
  const branchName = new TextDecoder().decode(branchResult.stdout).trim()

  return branchName ? `${repoName} (${branchName})` : repoName
}

const main = async () => {
  const input = await new Response(Deno.stdin.readable).text()
  const method = detectNotifyMethod()

  try {
    const data: HookData = JSON.parse(input)
    const repoInfo = await getRepoInfo()

    const content: NotificationContent = (() => {
      if (data.hook_event_name === "Stop") {
        return {
          title: "⚡ Claude Code",
          subtitle: `${repoInfo} 📦`,
          body: "Task Completed 🚀",
          sound: "Glass",
        }
      } else if (data.hook_event_name === "Notification") {
        return {
          title: "⚡ Claude Code",
          subtitle: `${repoInfo} 📦`,
          body: "Awaiting Confirmation 🔔",
          sound: "Ping",
        }
      } else {
        throw new Error("unknown hook event")
      }
    })()

    await sendNotification(method, content)
    console.log(JSON.stringify({ success: true }))
  } catch (error) {
    console.log(
      JSON.stringify({
        success: false,
        error: error instanceof Error ? error.message : String(error),
      }),
    )

    try {
      await sendNotification(method, {
        title: "Claude Code Error 🚨",
        subtitle: "",
        body: "Hook Failed!",
        sound: "Basso",
      })
    } catch {
      // Ignore notification errors in error handler
    }
  }
}

await main()
