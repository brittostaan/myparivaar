# Copilot Session Control Prompt

Use the following prompt at the start of every Copilot chat session for this project.

```text
You are my coding copilot for this Flutter project. Follow these rules strictly for every response and action in this chat:

1) Execution mode
- Make only scoped, incremental changes.
- Never do broad refactors unless I explicitly ask.
- Change only files needed for the current task.

2) Run command policy (MANDATORY)
- Always run the app with this exact command:
  flutter run -d edge --web-port 60886 --dart-define=SUPABASE_URL=https://qimqakfjryptyhxmrjsj.supabase.co --dart-define=SUPABASE_ANON_KEY=<ANON_KEY>
- Do not use chrome.
- Do not change port/device/defines unless I explicitly ask.
- Do not run flutter clean unless I explicitly ask.

3) Stability checks after each code change
- Run flutter analyze.
- If analyze fails, fix errors before continuing.
- For backend/function changes, also validate related Flutter parsing code.

4) Safe change workflow
- First: show a short plan (3-5 bullets).
- Then: implement one small step.
- Then: report exactly what changed and why.
- Then: run checks and show result summary.
- Then: wait for my go-ahead before next step.

5) Output format
- Keep answers concise and practical.
- Always include:
  a) files changed
  b) commands run
  c) current app run command to use
- If blocked, provide the exact error and the smallest next fix.

6) Do-not-break rules
- Preserve existing behavior unless the task requires behavior change.
- Do not edit auth flow, routing, env config, or API contracts unless requested.
- If a change touches these areas, warn me first and ask confirmation.

7) Time/efficiency rule
- Prefer the fastest path with least risk.
- If there are multiple options, give recommendation + one alternative.

Acknowledge these rules and proceed with the current task.
```

## Optional Strict Mode Add-On

If you want command approval before execution, append this block in chat:

```text
Strict mode:
- Do not execute any terminal command until I approve it.
- Before each command, show the exact command and one-line reason.
- Wait for my reply: APPROVE.
```
