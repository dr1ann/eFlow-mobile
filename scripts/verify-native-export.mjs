import { execFileSync } from "node:child_process";
import { existsSync, rmSync } from "node:fs";
import { relative, resolve } from "node:path";

const workspace = resolve(import.meta.dirname, "..");
const outputRoot = resolve(workspace, "dist", "native-export");
const expoCli = resolve(workspace, "node_modules", "expo", "bin", "cli");

const outputRelative = relative(workspace, outputRoot);
if (outputRelative.startsWith("..") || outputRelative === "") {
  throw new Error("Refusing to remove a build directory outside the workspace.");
}

if (existsSync(outputRoot)) {
  rmSync(outputRoot, { recursive: true, force: true });
}

if (!existsSync(expoCli)) {
  throw new Error("Expo is not installed. Run npm install before native export verification.");
}

for (const platform of ["android", "ios"]) {
  execFileSync(
    process.execPath,
    [expoCli, "export", "--platform", platform, "--output-dir", resolve(outputRoot, platform)],
    { cwd: workspace, stdio: "inherit" }
  );
}
