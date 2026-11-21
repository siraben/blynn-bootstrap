import { createKernel } from './sdk/dist/web.mjs';

const start = document.querySelector('#start');
const output = document.querySelector('#output');
start.onclick = async () => {
  start.disabled = true;
  output.textContent = 'Loading checkpoint…\n';
  let vm;
  try {
    const response = await fetch('./checkpoint.tar.gz');
    if (!response.ok) throw new Error(`Checkpoint download failed: ${response.status}`);
    const checkpoint = new Uint8Array(await response.arrayBuffer());
    const boot = performance.now();
    vm = await createKernel({
      memoryMiB: 256,
      mounts: { '/mnt/checkpoint': { 'checkpoint.tar.gz': checkpoint } },
    });
    const ready = await vm.exec('uname', ['-m']);
    if (ready.exitCode !== 0 || ready.stdout.trim() !== 'aarch64') throw new Error('Expected an AArch64 guest');
    output.textContent += `AArch64 guest ready in ${((performance.now() - boot) / 1000).toFixed(2)} s\nRebuilding TinyCC…\n`;
    const begin = performance.now();
    const result = await vm.exec('sh', ['-ec', 'mkdir /bootstrap; tar -xzf /mnt/checkpoint/checkpoint.tar.gz -C /bootstrap; sh /bootstrap/bootstrap.sh']);
    output.textContent += result.stdout + result.stderr;
    if (result.exitCode !== 0) throw new Error(`Bootstrap failed: ${result.exitCode}`);
    output.textContent += `Bootstrap and fixpoint check: ${((performance.now() - begin) / 1000).toFixed(2)} s\n`;
    output.dataset.status = 'passed';
  } catch (error) {
    output.textContent += `${error}\n`;
    output.dataset.status = 'failed';
  } finally {
    await vm?.stop();
    start.disabled = false;
  }
};
