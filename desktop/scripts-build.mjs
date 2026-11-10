import { spawn } from "node:child_process";
import { binaryPath } from "mygo-cli";

/** 使用同一构建入口生成 Windows 两种架构，避免依赖 shell 环境变量语法。 */
function buildWindows() {
  const child = spawn(binaryPath(), ["build", "-platform", "windows/amd64,windows/arm64"], {
    cwd: new URL(".", import.meta.url), stdio: "inherit",
    env: { ...process.env, SYNOMUSIC_BUILD_TARGET: "windows" },
  });
  child.on("error", error => { console.error(error.message); process.exitCode = 1; });
  child.on("exit", code => { process.exitCode = code ?? 1; });
}

buildWindows();
