import { createKernel } from './sdk/dist/web.mjs';

const start = document.querySelector('#start');
const status = document.querySelector('#status');
const container = document.querySelector('#terminal');
const terminal = new window.Terminal({ cursorBlink: true, theme: { background: '#0a0e14' } });
const fit = new window.FitAddon.FitAddon();
terminal.loadAddon(fit);
terminal.open(container);
fit.fit();
new ResizeObserver(() => fit.fit()).observe(container);

const fromSeed = new URLSearchParams(location.search).has('stage0');
const archive = fromSeed ? 'stage0.tar.gz' : 'checkpoint.tar.gz';
const command = fromSeed ? 'bootstrap-from-seed' : 'bootstrap';
const prepare = fromSeed
  ? 'mkdir /seed; tar -xzf /mnt/payload/stage0.tar.gz -C /seed; chmod -R u+w /seed; chmod +x /seed/stage0.sh /seed/from-seed.sh; ln -s /seed/stage0.sh /bin/bootstrap-stage0; ln -s /seed/from-seed.sh /bin/bootstrap-from-seed'
  : 'mkdir /bootstrap; tar -xzf /mnt/payload/checkpoint.tar.gz -C /bootstrap; chmod +x /bootstrap/bootstrap.sh; ln -s /bootstrap/bootstrap.sh /bin/bootstrap';
if (fromSeed) {
  start.textContent = 'Bootstrap from seed';
  document.querySelector('#mode-help').textContent = 'Run bootstrap-from-seed for hex0 → stage0 → Blynn → HCC → TinyCC, or bootstrap-stage0 for just the verified tools.';
}

let vm;
let ready = false;
let consoleBytes = 0;
let timer;
let previousCpu;
const cpu = document.querySelector('#cpu');
const disk = document.querySelector('#disk');
const tty = document.querySelector('#tty');
const kib = n => `${(n / 1024).toFixed(1)} KiB`;

async function sample() {
  if (!ready) return;
  try {
    const { block } = vm.stats();
    disk.textContent = `Block I/O: ↓ ${kib(block.bytesRead)} ↑ ${kib(block.bytesWritten)}`;
    tty.textContent = `Console out: ${kib(consoleBytes)}`;
    const result = await vm.exec('head', ['-n', '1', '/proc/stat']);
    if (!ready) return;
    const ticks = result.stdout.trim().split(/\s+/).slice(1, 9).map(Number);
    if (result.exitCode === 0 && ticks.length === 8 && ticks.every(Number.isFinite)) {
      const total = ticks.reduce((sum, ticks) => sum + ticks, 0);
      const idle = ticks[3] + ticks[4];
      if (previousCpu && total > previousCpu.total) {
        const busy = 1 - (idle - previousCpu.idle) / (total - previousCpu.total);
        cpu.textContent = `Guest CPU: ${Math.round(Math.max(0, Math.min(1, busy)) * 100)}%`;
      }
      previousCpu = { total, idle };
    }
  } catch {
    cpu.textContent = 'Guest CPU: —';
  } finally {
    if (ready) timer = setTimeout(sample, 2000);
  }
}
terminal.onData(data => { if (ready) vm.write(data); });
terminal.onResize(({ cols, rows }) => vm?.resize(cols, rows));
start.onclick = () => {
  terminal.focus();
  vm.write(`${command}\r`);
};

try {
  terminal.writeln(`Loading ${archive}…`);
  const response = await fetch(`./${archive}`);
  if (!response.ok) throw new Error(`${archive} download failed: ${response.status}`);
  const payload = new Uint8Array(await response.arrayBuffer());
  const boot = performance.now();
  vm = await createKernel({
    memoryMiB: fromSeed ? 2048 : 256,
    consoleSize: { cols: terminal.cols, rows: terminal.rows },
    mounts: { '/mnt/payload': { [archive]: payload } },
    onOutput: bytes => {
      consoleBytes += bytes.byteLength;
      terminal.write(bytes);
    },
  });
  vm.resize(terminal.cols, terminal.rows);
  const setup = await vm.exec('sh', ['-ec', `test "$(uname -m)" = aarch64; ${prepare}`]);
  if (setup.exitCode !== 0) throw new Error(setup.stderr.trim() || `Guest setup failed: ${setup.exitCode}`);
  status.textContent = `AArch64 · ${((performance.now() - boot) / 1000).toFixed(2)} s to ready`;
  ready = true;
  start.disabled = false;
  terminal.focus();
  sample();
  const { kind, code } = await vm.exited;
  ready = false;
  start.disabled = true;
  status.textContent = `Guest stopped (${kind}, ${code}) · reload to restart`;
} catch (error) {
  ready = false;
  start.disabled = true;
  status.textContent = 'Guest failed';
  terminal.writeln(`\r\n${error}`);
  await vm?.stop();
} finally {
  clearTimeout(timer);
}
