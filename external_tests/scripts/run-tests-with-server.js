#!/usr/bin/env node

/**
 * Start the Rails server (if not running) and run Playwright tests.
 * The server runs visibly in the same terminal (not hidden/daemonized).
 *
 * Custom flags consumed by this script:
 *   --with-rspec                Run `bundle exec rspec` before integration tests
 *   --keep-server               Keep server running after tests when this script started it
 *   --allow-live-server-with-rspec
 *                               Allow rspec run even if a server is already live
 *   --open-report               Auto-serve Playwright HTML report after full suite
 *   --skip-test-data            Skip the rails test_data:setup step before Playwright
 *                               (use when you manage test data externally)
 */

const { spawn, spawnSync, execSync } = require('child_process');
const path = require('path');
const fs = require('fs');
const readline = require('readline');
const net = require('net');

const { getBaseURL, APP_PORT } = require('../config/test-config');

const BASE_URL = getBaseURL();

// Resolve the correct `bundle` executable once at startup.
// Version managers (RVM, rbenv, asdf) only add their shims to PATH after sourcing
// shell init files. We try two strategies in order:
//
//   1. The current process PATH (inherited from the terminal that ran `npm run`).
//      This is sufficient when the user's terminal already has the version manager
//      initialised — which is the common case.
//
//   2. A login shell using $SHELL (the user's actual shell, e.g. /bin/zsh on
//      modern macOS). This sources ~/.zprofile / ~/.bash_profile and picks up
//      RVM/rbenv even when strategy 1 misses it. We intentionally use $SHELL
//      rather than hardcoding bash because RVM on macOS typically lives in
//      ~/.zshrc / ~/.zprofile, not ~/.bash_profile.
function detectBundlePath() {
  // Strategy 1: use the PATH already in the current Node process.
  const direct = spawnSync('which', ['bundle'], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    shell: false
  });
  const directPath = (direct.stdout || '').trim();
  if (directPath) return directPath;

  // Strategy 2: login shell with the user's actual shell.
  const userShell = process.env.SHELL || '/bin/bash';
  const login = spawnSync(userShell, ['-l', '-c', 'which bundle'], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe']
  });
  const loginPath = (login.stdout || '').trim();
  if (loginPath) return loginPath;

  console.warn('⚠ Could not detect bundle path; falling back to "bundle". Set BUNDLE_BIN env var to override.');
  return 'bundle';
}

const BUNDLE_BIN = process.env.BUNDLE_BIN || detectBundlePath();

const SERVER_START_TIMEOUT = 30000; // 30 seconds
const SERVER_CHECK_INTERVAL = 2000; // 2 seconds

let serverProcess = null;
let serverStartedByScript = false;
let serverStartedInSeparateWindow = false;
let serverWindowPid = null;
let serverWindowCanBeStopped = false;
let keepServerRunning = false;
let shutdownInProgress = false;

const BOLD = '\x1b[1m';
const RESET = '\x1b[0m';

function resolveServerDir() {
  const envServerDir = process.env.GUILDSYNC_SERVER_DIR;
  const candidates = [
    envServerDir,
    path.resolve(__dirname, '../../guildsync')
  ].filter(Boolean);

  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) {
      return candidate;
    }
  }

  return null;
}

const SERVER_DIR = resolveServerDir();

function parseArgs(rawArgs) {
  const args = [...rawArgs];
  const extracted = {
    withRspec: false,
    keepServer: false,
    allowLiveServerWithRspec: false,
    assumeYes: false,
    inlineServer: false,
    openReport: false,
    skipTestData: false,
    playwrightArgs: []
  };

  for (const arg of args) {
    if (arg === '--with-rspec') {
      extracted.withRspec = true;
      continue;
    }
    if (arg === '--keep-server') {
      extracted.keepServer = true;
      continue;
    }
    if (arg === '--allow-live-server-with-rspec') {
      extracted.allowLiveServerWithRspec = true;
      continue;
    }
    if (arg === '--yes' || arg === '-y' || arg === '--no-confirm') {
      extracted.assumeYes = true;
      continue;
    }
    if (arg === '--inline-server') {
      extracted.inlineServer = true;
      continue;
    }
    if (arg === '--open-report') {
      extracted.openReport = true;
      continue;
    }
    if (arg === '--skip-test-data') {
      extracted.skipTestData = true;
      continue;
    }
    extracted.playwrightArgs.push(arg);
  }

  return extracted;
}

function shouldUseSeparateServerWindow(parsedArgs) {
  return process.env.GUILDSYNC_SERVER_NEW_WINDOW !== '0' &&
    !parsedArgs.inlineServer;
}

function getServerTerminalModeLabel(parsedArgs) {
  if (!shouldUseSeparateServerWindow(parsedArgs)) {
    return 'same terminal (inline)';
  }

  if (process.platform === 'win32') {
    return 'separate terminal window (cmd.exe)';
  }
  if (process.platform === 'darwin') {
    return 'separate terminal window (Terminal.app)';
  }
  return 'separate terminal window (system terminal)';
}

function shellQuoteSingle(value) {
  return `'${String(value).replace(/'/g, `'\\''`)}'`;
}

function spawnDetached(command, args, options = {}) {
  const child = spawn(command, args, {
    detached: true,
    stdio: 'ignore',
    windowsHide: false,
    ...options
  });
  child.unref();
  return child;
}

function launchServerInSeparateWindow(serverDir, railsEnv) {
  if (process.platform === 'win32') {
    const windowsCommand = `set "RAILS_ENV=${railsEnv}" && bundle exec rails server -e ${railsEnv}`;
    const child = spawnDetached('cmd.exe', ['/d', '/k', windowsCommand], {
      cwd: serverDir,
      env: { ...process.env, RAILS_ENV: railsEnv }
    });

    return { ok: true, pid: child.pid, canStop: true, detail: 'cmd.exe' };
  }

  const unixCommand = `cd ${shellQuoteSingle(serverDir)}; RAILS_ENV=${shellQuoteSingle(railsEnv)} bundle exec rails server -e ${shellQuoteSingle(railsEnv)}`;

  if (process.platform === 'darwin') {
    // Use a multi-statement script so Terminal.app is activated (brought to front /
    // un-minimised) before the new script window is opened. The single-line
    // "do script" form opens a background tab when Terminal is already running
    // minimised, which makes the server invisible to the user.
    const osaScript = [
      'tell application "Terminal"',
      '  activate',
      `  do script ${JSON.stringify(unixCommand)}`,
      'end tell'
    ].join('\n');
    const result = spawnSync('osascript', ['-e', osaScript], { encoding: 'utf8' });
    if (result.status === 0) {
      return { ok: true, pid: null, canStop: false, detail: 'Terminal.app' };
    }
    return {
      ok: false,
      error: (result.stderr || result.stdout || 'osascript failed').trim()
    };
  }

  const linuxCandidates = [
    { cmd: 'x-terminal-emulator', args: ['-e', 'bash', '-lc', unixCommand] },
    { cmd: 'gnome-terminal', args: ['--', 'bash', '-lc', unixCommand] },
    { cmd: 'konsole', args: ['-e', 'bash', '-lc', unixCommand] },
    { cmd: 'xfce4-terminal', args: ['-e', `bash -lc ${shellQuoteSingle(unixCommand)}`] },
    { cmd: 'xterm', args: ['-e', 'bash', '-lc', unixCommand] }
  ];

  for (const candidate of linuxCandidates) {
    const probe = spawnSync(candidate.cmd, ['--version'], { encoding: 'utf8' });
    if (probe.error || probe.status !== 0) {
      continue;
    }

    const child = spawnDetached(candidate.cmd, candidate.args, { env: { ...process.env } });
    return { ok: true, pid: child.pid, canStop: true, detail: candidate.cmd };
  }

  return {
    ok: false,
    error: 'No supported Linux terminal executable found (x-terminal-emulator/gnome-terminal/konsole/xfce4-terminal/xterm).'
  };
}

function isInteractiveSession() {
  return Boolean(process.stdin.isTTY && process.stdout.isTTY && !process.env.CI);
}

function getRepoInfo(startDir) {
  if (!startDir || !fs.existsSync(startDir)) {
    return { root: null, branch: 'unavailable' };
  }

  try {
    const root = execSync('git rev-parse --show-toplevel', {
      cwd: startDir,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore']
    }).trim();

    const branch = execSync('git rev-parse --abbrev-ref HEAD', {
      cwd: root,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore']
    }).trim();

    return { root, branch };
  } catch (_) {
    return { root: null, branch: 'unavailable' };
  }
}

function getExpectedPort() {
  const { URL } = require('url');
  const parsedUrl = new URL(BASE_URL);
  if (parsedUrl.port) {
    return Number(parsedUrl.port);
  }
  return parsedUrl.protocol === 'https:' ? 443 : APP_PORT;
}

function getHostCandidates(hostname) {
  if (hostname === 'localhost') {
    return ['localhost', '127.0.0.1', '::1'];
  }
  return [hostname];
}

function checkSingleHostPortInUse(hostname, port) {
  return new Promise((resolve) => {
    const socket = new net.Socket();

    socket.setTimeout(1500);

    socket.once('connect', () => {
      socket.destroy();
      resolve(true);
    });

    socket.once('timeout', () => {
      socket.destroy();
      resolve(false);
    });

    socket.once('error', () => {
      resolve(false);
    });

    socket.connect(port, hostname);
  });
}

async function checkPortInUse(hostname, port) {
  const hostCandidates = getHostCandidates(hostname);
  for (const host of hostCandidates) {
    if (await checkSingleHostPortInUse(host, port)) {
      return true;
    }
  }
  return false;
}

function checkServerAtHost(hostname, port, timeout = 2000) {
  const http = require('http');
  return new Promise((resolve) => {
    const options = {
      hostname,
      port,
      path: '/',
      method: 'HEAD',
      timeout
    };

    const req = http.request(options, () => resolve(true));
    req.on('error', () => resolve(false));
    req.on('timeout', () => {
      req.destroy();
      resolve(false);
    });
    req.end();
  });
}

function printStartupConfig(parsedArgs, preflight) {
  const testsRepoInfo = getRepoInfo(path.resolve(__dirname, '..'));
  const appRepoInfo = SERVER_DIR ? getRepoInfo(SERVER_DIR) : { root: null, branch: 'unavailable' };
  const mode = parsedArgs.withRspec ? 'RSpec + Playwright' : 'Playwright only';
  const serverWindowMode = getServerTerminalModeLabel(parsedArgs);
  const portStatus = preflight.portInUse ? 'in use (existing process detected)' : 'available (no listener detected)';
  const httpStatus = preflight.serverResponding ? 'responding at base URL' : 'not responding at base URL';
  const railsEnv = process.env.RAILS_ENV || 'development';
  const railsEnvSource = process.env.RAILS_ENV ? 'from RAILS_ENV env var' : 'default (RAILS_ENV not set)';

  console.log(`\n${BOLD}============================================================${RESET}`);
  console.log(`${BOLD}RUN CONFIGURATION (CONFIRM BEFORE START)${RESET}`);
  console.log(`${BOLD}============================================================${RESET}`);
  console.log(`${BOLD}external_tests${RESET}`);
  console.log(`  repo: ${testsRepoInfo.root || 'unavailable'}`);
  console.log(`  branch: ${testsRepoInfo.branch}`);
  console.log(`${BOLD}GuildSync (Rails app)${RESET}`);
  console.log(`  repo: ${appRepoInfo.root || 'unavailable'}`);
  console.log(`  branch: ${appRepoInfo.branch}`);
  console.log(`${BOLD}orchestration${RESET}`);
  console.log(`  rails app dir: ${SERVER_DIR || 'unavailable'}`);
  console.log(`  bundle: ${BUNDLE_BIN}`);
  console.log(`  rails env: ${railsEnv} (${railsEnvSource})`);
  console.log(`  base url: ${BASE_URL}`);
  console.log(`  expected port ${preflight.expectedPort}: ${portStatus}`);
  console.log(`  server health check: ${httpStatus}`);
  if (preflight.portInUse && !preflight.serverResponding) {
    console.log('  note: port is occupied but HEAD check failed; startup will be skipped to avoid conflicts');
  }
  if (preflight.serverResponding && !parsedArgs.skipTestData) {
    console.log(`  ${BOLD}⚠ existing server detected — ensure it was started with RAILS_ENV=${railsEnv}${RESET}`);
    console.log(`    seed data and tests must target the same database; restart the server if in doubt`);
  }
  console.log(`  mode: ${mode}`);
  console.log(`  server terminal: ${serverWindowMode}`);
  console.log(`  auto-open html report: ${parsedArgs.openReport ? 'yes' : 'no'}`);
  console.log(`  keep server: ${parsedArgs.keepServer ? 'yes' : 'no'}`);
  console.log(`${BOLD}============================================================${RESET}\n`);
}

async function confirmStartupConfigIfNeeded(parsedArgs) {
  if (parsedArgs.assumeYes || !isInteractiveSession()) {
    return true;
  }

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
  });

  const answer = await new Promise((resolve) => {
    rl.question(`${BOLD}Proceed with this configuration? [y/N]: ${RESET}`, (response) => {
      resolve((response || '').trim().toLowerCase());
    });
  });

  rl.close();
  return answer === 'y' || answer === 'yes';
}

// Check if server is already running
async function checkServer() {
  const { URL } = require('url');
  
  const parsedUrl = new URL(BASE_URL);
  const port = parsedUrl.port || APP_PORT;
  const hostCandidates = getHostCandidates(parsedUrl.hostname);

  for (const host of hostCandidates) {
    if (await checkServerAtHost(host, port, 2000)) {
      return true;
    }
  }

  return false;
}

// Wait for server to be ready
async function waitForServer(maxWait = SERVER_START_TIMEOUT) {
  const startTime = Date.now();
  
  while (Date.now() - startTime < maxWait) {
    if (await checkServer()) {
      return true;
    }
    await new Promise(resolve => setTimeout(resolve, SERVER_CHECK_INTERVAL));
  }
  
  return false;
}

// Start the Rails server
async function startServer(parsedArgs) {
  if (!SERVER_DIR || !fs.existsSync(SERVER_DIR)) {
    console.error(`✗ Server directory not found: ${SERVER_DIR}`);
    console.error('  Set GUILDSYNC_SERVER_DIR, or ensure one of these exists:');
    console.error('  - ../../guildsync (repo root: GuildSync/)');
    process.exit(1);
  }

  // Default to development — that is the environment Rails uses when you run
  // `rails server` without an explicit RAILS_ENV, and Playwright tests hit that
  // server. Pass RAILS_ENV=test explicitly if you want an isolated test database.
  const railsEnv = process.env.RAILS_ENV || 'development';
  const useSeparateWindow = shouldUseSeparateServerWindow(parsedArgs);

  if (useSeparateWindow) {
    console.log(`Starting Rails server in a separate terminal window...`);
    console.log(`Server directory: ${SERVER_DIR}`);
    console.log(`Using environment: ${railsEnv}`);

    const launched = launchServerInSeparateWindow(SERVER_DIR, railsEnv);
    if (!launched.ok) {
      console.log('⚠ Could not launch a separate server terminal.');
      console.log(`  ${launched.error}`);
      console.log('  Falling back to inline server startup in this terminal.\n');
    } else {
      serverWindowPid = launched.pid || null;
      serverWindowCanBeStopped = Boolean(launched.canStop);
      serverStartedByScript = true;
      serverStartedInSeparateWindow = true;

      if (serverWindowPid) {
        console.log(`Opened server terminal via ${launched.detail} (pid: ${serverWindowPid}).`);
      } else {
        console.log(`Opened server terminal via ${launched.detail}.`);
      }
    }
  }

  if (!serverStartedInSeparateWindow) {
    console.log(`Starting Rails server in ${SERVER_DIR}...`);
    console.log(`Using environment: ${railsEnv}`);
    console.log('Server output is attached below:\n');

    // Use -e flag instead of RAILS_ENV env var for Windows compatibility.
    // Keep stdio inherited so the server is visible in the terminal.
    serverProcess = spawn(BUNDLE_BIN, ['exec', 'rails', 'server', '-e', railsEnv], {
      cwd: SERVER_DIR,
      stdio: 'inherit',
      shell: false,
      env: { ...process.env }
    });

    serverProcess.on('error', (err) => {
      console.error(`✗ Failed to start server: ${err.message}`);
      process.exit(1);
    });

    serverStartedByScript = true;
  }
  
  // Wait for server to be ready
  console.log(`Waiting for server to start at ${BASE_URL}...`);
  const serverReady = await waitForServer();
  
  if (!serverReady) {
    console.error(`✗ Server failed to start within ${SERVER_START_TIMEOUT / 1000} seconds`);
    if (serverStartedInSeparateWindow) {
      console.error('  The server terminal was left open so you can inspect startup errors.');
      process.exit(1);
    }
    await stopServer();
    process.exit(1);
  }
  
  console.log(`✓ Server is running at ${BASE_URL}`);
}

// Stop the server.
// Returns a Promise that resolves once the inline server process has actually exited
// (or immediately for external/window-managed servers where we have no exit event).
// Callers MUST await this before calling process.exit() to avoid orphaning Rails.
function stopServer() {
  if (serverStartedByScript && serverStartedInSeparateWindow) {
    if (serverWindowPid && serverWindowCanBeStopped && process.platform === 'win32') {
      console.log('\nStopping server terminal...');
      spawnSync('taskkill', ['/PID', String(serverWindowPid), '/T', '/F'], {
        stdio: 'ignore',
        shell: true
      });
      return Promise.resolve();
    }

    if (serverWindowPid && serverWindowCanBeStopped && process.platform !== 'win32') {
      console.log('\nStopping server terminal...');
      try {
        process.kill(-serverWindowPid, 'SIGTERM');
      } catch (_) {
        try {
          process.kill(serverWindowPid, 'SIGTERM');
        } catch (_) {
          // Best effort shutdown for detached terminal process.
        }
      }
      return Promise.resolve();
    }

    console.log('\nServer was started in a separate terminal window.');
    console.log('Please close that terminal manually when finished.');
    return Promise.resolve();
  }

  if (serverProcess && serverStartedByScript) {
    // Nothing to do if it already exited (e.g. crashed earlier).
    if (serverProcess.exitCode !== null || serverProcess.killed) {
      return Promise.resolve();
    }

    console.log('\nStopping server...');
    return new Promise((resolve) => {
      let forceKillTimer;

      serverProcess.once('exit', () => {
        clearTimeout(forceKillTimer);
        resolve();
      });

      serverProcess.kill('SIGTERM');

      // Force kill after 5 seconds if Rails has not exited gracefully.
      forceKillTimer = setTimeout(() => {
        if (serverProcess && serverProcess.exitCode === null && !serverProcess.killed) {
          console.log('  Server did not exit gracefully — force-killing (SIGKILL)...');
          serverProcess.kill('SIGKILL');
        }
      }, 5000);
    });
  }

  return Promise.resolve();
}

async function handleShutdown(signalName, exitCode) {
  if (shutdownInProgress) {
    console.log(`\n${signalName} received again, forcing exit now.`);
    process.exit(exitCode);
    return;
  }

  shutdownInProgress = true;
  console.log(`\n\n${signalName} received. Cleaning up...`);
  await stopServer();
  process.exit(exitCode);
}

function runRspec() {
  const railsEnv = process.env.RAILS_ENV || 'development';
  console.log(`\nRunning unit/spec tests first (RAILS_ENV=${railsEnv})...\n`);

  return new Promise((resolve) => {
    const rspecProcess = spawn(BUNDLE_BIN, ['exec', 'rspec'], {
      cwd: SERVER_DIR,
      stdio: 'inherit',
      shell: false,
      env: { ...process.env, RAILS_ENV: railsEnv }
    });

    rspecProcess.on('close', (code) => resolve(code || 0));
    rspecProcess.on('error', (err) => {
      console.error(`✗ Failed to run rspec: ${err.message}`);
      resolve(1);
    });
  });
}

// Ensure the database schema is up to date before seeding.
//   test env  → db:test:prepare  (purges test DB — requires no Rails connections to that DB)
//   other env → db:migrate       (runs pending migrations against the target DB)
function runDbPrepare(railsEnv) {
  const command = railsEnv === 'test' ? 'db:test:prepare' : 'db:migrate';
  console.log(`\nPreparing database (rails ${command}, RAILS_ENV=${railsEnv})...`);

  return new Promise((resolve) => {
    const proc = spawn(BUNDLE_BIN, ['exec', 'rails', command], {
      cwd: SERVER_DIR,
      stdio: 'inherit',
      shell: false,
      env: { ...process.env, RAILS_ENV: railsEnv }
    });

    proc.on('close', (code) => resolve(code || 0));
    proc.on('error', (err) => {
      console.error(`✗ Failed to run rails ${command}: ${err.message}`);
      resolve(1);
    });
  });
}

// Seed / re-sync integration test data (MFA user, free plan, etc.).
// The Rails script is idempotent: uses find_or_create_by! and re-syncs otp_secret
// to TEST_MFA_SECRET on every run, so calling this before every Playwright run is safe.
function runTestDataSetup(railsEnv) {
  console.log(`\nEnsuring integration test data is seeded (RAILS_ENV=${railsEnv})...`);

  const env = { ...process.env, RAILS_ENV: railsEnv };
  // Propagate TEST_MFA_SECRET so the seed script writes the same secret the OTP helper reads.
  // If neither side sets it, both fall back to the same compiled-in default (JBSWY3DPEHPK3PXP).
  if (process.env.TEST_MFA_SECRET) {
    env.TEST_MFA_SECRET = process.env.TEST_MFA_SECRET;
  }

  return new Promise((resolve) => {
    const setupProcess = spawn(
      BUNDLE_BIN,
      ['exec', 'rails', 'test_data:setup'],
      {
        cwd: SERVER_DIR,
        stdio: 'inherit',
        shell: false,
        env
      }
    );

    setupProcess.on('close', (code) => resolve(code || 0));
    setupProcess.on('error', (err) => {
      console.error(`✗ Failed to run test_data:setup: ${err.message}`);
      resolve(1);
    });
  });
}

// Check if this is a full suite run (no specific test files specified)
function isFullSuiteRun(args) {
  // Look for test paths - these are arguments that:
  // 1. Don't start with -- or - (not flags)
  // 2. Contain a path separator (/) or backslash (\)
  // 3. Or end with .spec.js, .spec.ts, .test.js, .test.ts
  // 4. Or are in the tests/ directory
  const testPaths = args.filter(arg => {
    // Skip flags and options
    if (arg.startsWith('--') || arg.startsWith('-')) {
      return false;
    }
    // Skip command names
    if (arg === 'test' || arg === 'playwright') {
      return false;
    }
    // Check if it looks like a test path
    return arg.includes('/') || 
           arg.includes('\\') || 
           arg.endsWith('.spec.js') || 
           arg.endsWith('.spec.ts') || 
           arg.endsWith('.test.js') || 
           arg.endsWith('.test.ts') ||
           arg.startsWith('tests/') ||
           arg.startsWith('tests\\');
  });
  
  // If any test paths are found, it's NOT a full suite run
  return testPaths.length === 0;
}

// Run Playwright tests
async function runTests() {
  const { playwrightArgs } = parseArgs(process.argv.slice(2));
  const testCommand = ['playwright', 'test', ...playwrightArgs];
  const isFullSuite = isFullSuiteRun(playwrightArgs);
  
  // Log detection result for debugging
  const testPaths = playwrightArgs.filter(arg => 
    !arg.startsWith('--') && 
    !arg.startsWith('-') && 
    arg !== 'test' && 
    arg !== 'playwright' &&
    (arg.includes('/') || arg.includes('\\') || arg.endsWith('.spec.js') || arg.endsWith('.spec.ts'))
  );
  if (testPaths.length > 0) {
    console.log(`[INFO] Detected test path(s): ${testPaths.join(', ')}`);
  }
  
  // Set environment variable to control HTML reporter behavior
  // This will be read by playwright.config.js
  process.env.PLAYWRIGHT_FULL_SUITE = isFullSuite ? '1' : '0';
  
  console.log(`\nRunning tests: ${testCommand.join(' ')}\n`);
  
  return new Promise((resolve) => {
    const testProcess = spawn('npx', testCommand, {
      stdio: 'inherit',
      shell: true,
      env: { ...process.env, PLAYWRIGHT_FULL_SUITE: isFullSuite ? '1' : '0' }
    });

    testProcess.on('close', (code) => {
      resolve({ code, isFullSuite });
    });

    testProcess.on('error', (err) => {
      console.error(`✗ Failed to run tests: ${err.message}`);
      resolve({ code: 1, isFullSuite });
    });
  });
}

function maybeOpenHtmlReport(parsedArgs, isFullSuite) {
  if (!isFullSuite) {
    console.log('\nℹ Specific test run detected - skipping auto-open');
    console.log('  Run `npm run test:report` to view the HTML report');
    return;
  }

  if (!parsedArgs.openReport) {
    console.log('\nℹ Full suite run complete.');
    console.log('  Report not auto-opened by default to avoid blocking the orchestrator.');
    console.log('  Run `npm run test:report` to serve the HTML report when needed.');
    console.log('  Or re-run with `--open-report` to auto-serve it.');
    return;
  }

  console.log('\n✓ Full suite run detected - starting HTML report server...');
  const reportProcess = spawn('npx', ['playwright', 'show-report'], {
    stdio: 'ignore',
    shell: true,
    detached: true
  });
  reportProcess.unref();
  console.log('  HTML report server started in background.');
  console.log('  Run `npm run test:report` if you want an interactive foreground session.');
}

// Cleanup on exit
process.on('SIGINT', () => handleShutdown('SIGINT (Ctrl+C)', 130));

process.on('SIGTERM', () => {
  handleShutdown('SIGTERM', 0);
});

// Main execution
async function main() {
  try {
    const parsed = parseArgs(process.argv.slice(2));
    keepServerRunning = parsed.keepServer;
    const { URL } = require('url');
    const parsedUrl = new URL(BASE_URL);
    const expectedPort = getExpectedPort();
    const portInUse = await checkPortInUse(parsedUrl.hostname, expectedPort);
    const serverResponding = await checkServer();
    const preflight = { expectedPort, portInUse, serverResponding };

    printStartupConfig(parsed, preflight);
    const confirmed = await confirmStartupConfigIfNeeded(parsed);
    if (!confirmed) {
      console.log('\nRun cancelled by user before starting orchestration.');
      process.exit(1);
    }

    if (!SERVER_DIR) {
      console.error('✗ Could not locate the Rails app directory.');
      console.error('  Set GUILDSYNC_SERVER_DIR to your backend path.');
      process.exit(1);
    }

    const isRunning = preflight.serverResponding;
    const shouldSkipServerStart = preflight.portInUse;

    if (parsed.withRspec && shouldSkipServerStart && !parsed.allowLiveServerWithRspec) {
      console.error('✗ Refusing to run rspec while a server is already running.');
      console.error('  This avoids shared-state surprises between spec and integration runs.');
      console.error('  Stop the running server first, or re-run with --allow-live-server-with-rspec');
      process.exit(1);
    }

    if (parsed.withRspec) {
      const rspecExitCode = await runRspec();
      if (rspecExitCode !== 0) {
        console.error('\n✗ rspec failed. Skipping integration tests.');
        process.exit(rspecExitCode);
      }
      console.log('\n✓ rspec passed. Continuing with integration tests.\n');
    }

    const externalServerInUse = isRunning || shouldSkipServerStart;

    // Prepare DB before starting Rails. db:test:prepare drops the test database and fails
    // with PG::ObjectInUse if Puma (or any client) is already connected.
    if (!parsed.skipTestData) {
      const railsEnv = process.env.RAILS_ENV || 'development';

      if (externalServerInUse) {
        console.warn('\nℹ Skipping database prepare (a process is already listening on the target port).');
        console.warn(
          '  db:test:prepare cannot run while Rails holds connections to the database.'
        );
        console.warn(
          '  Stop that server and re-run, or ensure schema and test_data:setup are already current.\n'
        );
      } else {
        const dbExitCode = await runDbPrepare(railsEnv);
        if (dbExitCode !== 0) {
          console.error('\n✗ Database prepare failed. Skipping integration tests.');
          console.error('  Fix the migration error above or re-run with --skip-test-data to bypass.');
          process.exit(dbExitCode);
        }

        const setupExitCode = await runTestDataSetup(railsEnv);
        if (setupExitCode !== 0) {
          console.error('\n✗ test_data:setup failed. Skipping integration tests.');
          console.error('  Fix the seed error above or re-run with --skip-test-data to bypass.');
          process.exit(setupExitCode);
        }
        console.log('\n✓ Integration test data is ready.\n');
      }
    } else {
      console.log('\nℹ Skipping test_data:setup (--skip-test-data).\n');
    }

    if (isRunning) {
      console.log(`✓ Server is already running at ${BASE_URL}`);
      console.warn(
        `${BOLD}Tip:${RESET} This run uses that process as-is. After changing Rails config/initializers, restart it (or stop it and run this script alone so it starts a fresh server) — otherwise you may see stale errors (e.g. JWT/HMAC).`
      );
      console.log(`  Running tests against existing server...\n`);
    } else if (shouldSkipServerStart) {
      console.log(`⚠ Expected port ${preflight.expectedPort} is already in use.`);
      console.warn(
        `${BOLD}Tip:${RESET} Another process owns the port; tests hit it without starting Rails here. Restart that process after code changes if results look wrong.`
      );
      console.log('  Skipping Rails server startup and running tests against existing process.\n');
    } else {
      await startServer(parsed);
    }

    // Run tests
    const { code: exitCode, isFullSuite } = await runTests();
    
    // Auto-open HTML report only for full suite runs
    maybeOpenHtmlReport(parsed, isFullSuite);
    
    // Stop server only when this script started it and caller did not request keeping it.
    // Await the shutdown so Rails has fully exited before process.exit() is called —
    // without this the server would be orphaned and keep running in the background.
    if (serverStartedByScript && !keepServerRunning) {
      await stopServer();
    } else if (serverStartedByScript && keepServerRunning) {
      console.log('\n✓ Leaving server running (--keep-server).');
    }

    process.exit(exitCode);
  } catch (error) {
    console.error(`✗ Error: ${error.message}`);
    await stopServer();
    process.exit(1);
  }
}

main();

