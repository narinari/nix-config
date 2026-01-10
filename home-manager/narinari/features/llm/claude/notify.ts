interface HookData {
  session_id: string
  transcript_path: string
  hook_event_name: "Stop" | "Notification"
  stop_hook_active?: boolean
}

const main = async () => {
  const input = await new Response(Deno.stdin.readable).text()

  try {
    const data: HookData = JSON.parse(input)

    const currentDir = Deno.cwd()

    // Check if current directory is a git repository
    const gitCheckProcess = new Deno.Command("git", {
      args: ["rev-parse", "--is-inside-work-tree"],
      stdout: "piped",
      stderr: "piped",
    })

    const gitCheckResult = await gitCheckProcess.output()
    const isGitRepo =
      gitCheckResult.success && new TextDecoder().decode(gitCheckResult.stdout).trim() === "true"

    let repoInfo = ""

    if (isGitRepo) {
      // Get repository name from git remote
      const remoteProcess = new Deno.Command("git", {
        args: ["remote", "get-url", "origin"],
        stdout: "piped",
        stderr: "piped",
      })

      const remoteResult = await remoteProcess.output()
      const remoteUrl = new TextDecoder().decode(remoteResult.stdout).trim()

      let repoName = ""
      if (remoteUrl && remoteResult.success) {
        // Extract repo name from URL (supports both HTTPS and SSH formats)
        const match = remoteUrl.match(/[/:]([^/]+?)(?:\.git)?$/)
        repoName = match ? match[1] : ""
      }

      // Fallback to directory name if no git remote
      if (!repoName) {
        repoName = currentDir.split("/").pop() || ""
      }

      // Get current branch name
      const branchProcess = new Deno.Command("git", {
        args: ["branch", "--show-current"],
        stdout: "piped",
        stderr: "piped",
      })

      const branchResult = await branchProcess.output()
      const branchName = new TextDecoder().decode(branchResult.stdout).trim()

      repoInfo = branchName ? `${repoName} (${branchName})` : repoName
    } else {
      // Not a git repository, use directory name
      repoInfo = currentDir.split("/").pop() || ""
    }

    const message: string = (() => {
      if (data.hook_event_name === "Stop") {
        return `display notification "Task Completed 🚀" with title "⚡ Claude Code" subtitle "${repoInfo} 📦"`
      } else if (data.hook_event_name === "Notification") {
        return `display notification "Awaiting Confirmation 🔔" with title "⚡ Claude Code" subtitle "${repoInfo} 📦"`
      } else {
        throw new Error("unknown error")
      }
    })()

    const command: Deno.Command = new Deno.Command("nc", {
          args: ["-N", "localhost", "60000"],
          stdout: "piped",
          stderr: "piped",
        })

    const process = command.spawn()

    const writer = process.stdin.getWriter()
    await writer.write(new TextEncoder().encode(message))

    await process.output()

    console.log(JSON.stringify({ success: true }))
  } catch (error) {
    console.log(
      JSON.stringify({
        success: false,
        error: error instanceof Error ? error.message : String(error),
      }),
    )

    const command: Deno.Command =
        new Deno.Command("nc", {
          args: ["-N", "localhost", "60000"],
          stdout: "piped",
          stderr: "piped",
        })

    const process = command.spawn()

    const writer = process.stdin.getWriter()
    await writer.write(new TextEncoder().encode('display notification "Hook Failed !" with title "Claude Code Error 🚨"'))

    await process.output()
  }
}

await main()
