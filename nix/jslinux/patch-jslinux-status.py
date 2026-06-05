import pathlib
import sys


def main() -> None:
    path = pathlib.Path(sys.argv[1])
    text = path.read_text()
    replacements = {
        """function update_downloading(flag)
{
    var el;
""": """function update_downloading(flag)
{
    var el;
    if (window.setBootStatus) {
        window.setBootStatus(flag ? "Downloading VM block data..." : "VM block download complete; waiting for Linux output...");
    }
    if (window.setBootProgress) {
        window.setBootProgress(flag ? 0 : 1, 1);
    }
""",
        """function start_vm(user, pwd)
{
    var url, mem_size, cpu, params, vm_url, cmdline, cols, rows, guest_url;
""": """function start_vm(user, pwd)
{
    if (window.setBootStatus) {
        window.setBootStatus("Preparing JSLinux VM parameters...");
    }
    if (window.setBootProgress) {
        window.setBootProgress(0, 0);
    }
    var url, mem_size, cpu, params, vm_url, cmdline, cols, rows, guest_url;
""",
        """    function start()
    {
        /* C functions called from javascript */
""": """    function start()
    {
        if (window.setBootStatus) {
            window.setBootStatus("Starting VM: loading kernel and root disk...");
        }
        if (window.setBootProgress) {
            window.setBootProgress(0, 0);
        }
        /* C functions called from javascript */
""",
        """        term.write("Loading...\\r\\n");
""": """        term.write("Loading...\\r\\n");
        if (window.setBootStatus) {
            window.setBootStatus("Terminal ready; loading emulator runtime...");
        }
        if (window.setBootProgress) {
            window.setBootProgress(0, 0);
        }
""",
        """    Module.preRun = start;

    loadScript(vm_url, null);
""": """    Module.preRun = start;
    Module.monitorRunDependencies = function(left) {
        if (window.setBootStatus) {
            window.setBootStatus(left ? "Instantiating emulator WebAssembly..." : "Emulator ready; starting Linux kernel...");
        }
        if (window.setBootProgress) {
            window.setBootProgress(left ? 0 : 1, 1);
        }
    };

    if (window.setBootStatus) {
        window.setBootStatus("Loading emulator runtime " + vm_url + "...");
    }
    if (window.setBootProgress) {
        window.setBootProgress(0, 0);
    }
    loadScript(vm_url, null);
""",
    }
    for old, new in replacements.items():
        if old not in text:
            raise SystemExit(f"missing expected JSLinux snippet: {old[:60]!r}")
        text = text.replace(old, new, 1)
    path.write_text(text)


if __name__ == "__main__":
    main()
