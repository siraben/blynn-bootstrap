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

let vm;
let ready = false;
terminal.onData(data => { if (ready) vm.write(data); });
terminal.onResize(({ cols, rows }) => vm?.resize(cols, rows));
start.onclick = () => {
  terminal.focus();
  vm.write('bootstrap\r');
};

try {
  terminal.writeln('Loading the TinyCC checkpoint…');
  const response = await fetch('./checkpoint.tar.gz');
  if (!response.ok) throw new Error(`Checkpoint download failed: ${response.status}`);
  const checkpoint = new Uint8Array(await response.arrayBuffer());
  const boot = performance.now();
  vm = await createKernel({
    memoryMiB: 256,
    consoleSize: { cols: terminal.cols, rows: terminal.rows },
    mounts: { '/mnt/checkpoint': { 'checkpoint.tar.gz': checkpoint } },
    onOutput: bytes => terminal.write(bytes),
  });
  vm.resize(terminal.cols, terminal.rows);
  const setup = await vm.exec('sh', ['-ec', 'test "$(uname -m)" = aarch64; mkdir /bootstrap; tar -xzf /mnt/checkpoint/checkpoint.tar.gz -C /bootstrap; chmod +x /bootstrap/bootstrap.sh; ln -s /bootstrap/bootstrap.sh /bin/bootstrap']);
  if (setup.exitCode !== 0) throw new Error(setup.stderr.trim() || `Guest setup failed: ${setup.exitCode}`);
  status.textContent = `AArch64 · ${((performance.now() - boot) / 1000).toFixed(2)} s to ready`;
  ready = true;
  start.disabled = false;
  terminal.focus();
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
}
