// 配布用実行ファイルの確認。Windows CIとmacOSで同じ手順を実行できる。
const assert = require("node:assert/strict");
const {spawn, execFileSync} = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {setTimeout: delay} = require("node:timers/promises");
const {chromium} = require("playwright");

assert(process.argv[2], "実行ファイルのパスを指定してください");
const executable = path.resolve(process.argv[2]);
assert(fs.existsSync(executable), `実行ファイルがありません: ${executable}`);
const results = process.env.SMOKE_RESULTS_DIR || fs.mkdtempSync(path.join(os.tmpdir(), "susumi-smoke-"));
const dataDir = path.join(results, "data with spaces");
fs.mkdirSync(dataDir, {recursive: true});
const url = "http://localhost:4000/_check";
const processes = new Set();

function start(label) {
  const state = {log: "", error: null};
  const logFile = path.join(results, `${label}.log`);
  const child = spawn(executable, [], {
    env: {
      ...process.env,
      SUSUMI_DATA_DIR: dataDir,
      SUSUMI_INSTALL_DIR: path.join(results, "runtime"),
    },
    detached: process.platform !== "win32",
    stdio: ["ignore", "pipe", "pipe"],
  });
  state.child = child;
  processes.add(state);
  for (const stream of [child.stdout, child.stderr]) {
    stream.setEncoding("utf8");
    stream.on("data", (text) => {
      state.log += text;
      fs.appendFileSync(logFile, text);
    });
  }
  child.on("error", (error) => { state.error = error; });
  return state;
}

async function waitFor(check, message, timeout = 120_000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    if (await check()) return;
    await delay(250);
  }
  throw new Error(message);
}

async function ready(state) {
  await waitFor(async () => {
    if (state.error) throw state.error;
    assert.equal(state.child.exitCode, null, `起動中に終了しました:\n${state.log}`);
    try {
      return (await fetch(url, {signal: AbortSignal.timeout(2_000)})).ok;
    } catch {
      return false;
    }
  }, `起動がタイムアウトしました:\n${state.log}`);
}

function stop(state) {
  if (state.child.pid && state.child.exitCode === null) {
    if (process.platform === "win32") {
      execFileSync("taskkill", ["/PID", String(state.child.pid), "/T", "/F"], {stdio: "ignore"});
    } else {
      process.kill(-state.child.pid, "SIGKILL");
    }
  }
  processes.delete(state);
}

async function connected(page) {
  await page.goto(url);
  await page.locator('[data-phx-main].phx-connected').waitFor();
}

async function main() {
  let browser;
  let context;
  try {
    // 既存サーバーの応答を、この実行ファイルの成功と取り違えない。
    const net = require("node:net");
    await new Promise((resolve, reject) => {
      const server = net.createServer();
      server.once("error", reject);
      server.listen(4000, "0.0.0.0", () => server.close(resolve));
    });

    const first = start("first-start");
    await ready(first);
    for (const file of ["susumi.db", "secret_key_base", "config.json"]) {
      assert(fs.existsSync(path.join(dataDir, file)), `${file}が作成されていません`);
    }
    browser = await chromium.launch();
    context = await browser.newContext();
    await context.tracing.start({screenshots: true, snapshots: true});
    const a = await context.newPage();
    const b = await context.newPage();
    await connected(a);
    await connected(b);
    await a.getByText("回数: 0", {exact: true}).waitFor();
    await a.getByRole("button", {name: "+1", exact: true}).click();
    await a.getByText("回数: 1", {exact: true}).waitFor();
    await b.getByText("回数: 1", {exact: true}).waitFor();
    console.log("PASS: 起動・SQLite書き込み・2画面へのリアルタイム反映");

    const duplicate = start("duplicate-start");
    await waitFor(() => duplicate.log.includes("ポート4000は、ほかのソフトが使っています。"),
      "二重起動時の案内がありません");
    await waitFor(() => duplicate.child.exitCode !== null, "二重起動したプロセスが終了しません", 45_000);
    assert.notEqual(duplicate.child.exitCode, 0);
    processes.delete(duplicate);
    await a.getByRole("button", {name: "+1", exact: true}).click();
    await b.getByText("回数: 2", {exact: true}).waitFor();
    console.log("PASS: 二重起動の案内・終了・先に起動したサーバーの継続");

    stop(first);
    await waitFor(async () => {
      try {
        await fetch(url, {signal: AbortSignal.timeout(1_000)});
        return false;
      } catch {
        return true;
      }
    }, "停止後もサーバーが応答しています", 10_000);
    const restarted = start("restart");
    await ready(restarted);
    await connected(a);
    await a.getByText("回数: 2", {exact: true}).waitFor();
    console.log("PASS: 停止・再起動後のデータ保持");
  } finally {
    try {
      if (context) await context.tracing.stop({path: path.join(results, "trace.zip")});
      if (browser) await browser.close();
    } finally {
      for (const state of processes) stop(state);
    }
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
