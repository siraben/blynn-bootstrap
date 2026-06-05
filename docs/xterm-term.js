"use strict";

(function () {
  const encoder = new TextEncoder();

  function bytesToBinaryString(bytes) {
    let out = "";
    const chunkSize = 8192;
    for (let i = 0; i < bytes.length; i += chunkSize) {
      out += String.fromCharCode.apply(null, bytes.subarray(i, i + chunkSize));
    }
    return out;
  }

  function dataToBytes(data) {
    if (data instanceof Uint8Array) {
      return data;
    }
    const bytes = new Uint8Array(data.length);
    for (let i = 0; i < data.length; i++) {
      bytes[i] = data.charCodeAt(i) & 0xff;
    }
    return bytes;
  }

  function measureCell(container, fontSize) {
    const probe = document.createElement("span");
    probe.className = "xterm-measure-probe";
    probe.style.fontSize = `${fontSize}px`;
    probe.textContent = "W";
    container.appendChild(probe);
    const rect = probe.getBoundingClientRect();
    probe.remove();
    return {
      width: rect.width || fontSize * 0.62,
      height: rect.height || fontSize * 1.35,
    };
  }

  function Term(options) {
    this.w = options.cols || 80;
    this.h = options.rows || 25;
    this.font_size = options.fontSize || 15;
    this.handler = function () {};
    this.term_el = null;
    this.parent_el = null;
    this.xterm = new Terminal({
      cols: this.w,
      rows: this.h,
      scrollback: options.scrollback || 10000,
      fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace',
      fontSize: this.font_size,
      cursorBlink: true,
      convertEol: false,
      allowProposedApi: false,
      theme: {
        background: "#000000",
        foreground: "#f0f0f0",
        cursor: "#52ff7a",
        selectionBackground: "#315a7d",
      },
    });
  }

  Term.prototype.setKeyHandler = function (handler) {
    this.handler = handler;
  };

  Term.prototype.open = function (parentEl) {
    this.parent_el = parentEl;
    parentEl.classList.add("xterm-host");
    this.xterm.open(parentEl);
    this.term_el = this.xterm.element;
    this.term_el.style.width = "100%";
    this.term_el.style.minHeight = `${Math.ceil(this.h * this.font_size * 1.35)}px`;
    this.xterm.onKey(({ key }) => {
      this.handler(bytesToBinaryString(encoder.encode(key)));
    });
    parentEl.addEventListener("paste", (event) => {
      const text = event.clipboardData && event.clipboardData.getData("text/plain");
      if (text) {
        event.preventDefault();
        this.paste(text);
      }
    });
    this.xterm.focus();
  };

  Term.prototype.resizePixel = function (width, height) {
    if (!this.parent_el) {
      return false;
    }
    const cell = measureCell(this.parent_el, this.font_size);
    const cols = Math.max(20, Math.floor((width - 18) / cell.width));
    const rows = Math.max(5, Math.floor(height / cell.height));
    if (cols === this.w && rows === this.h) {
      return false;
    }
    this.w = cols;
    this.h = rows;
    this.xterm.resize(cols, rows);
    return true;
  };

  Term.prototype.write = function (data) {
    this.xterm.write(dataToBytes(data));
  };

  Term.prototype.writeln = function (data) {
    this.write(`${data}\r\n`);
  };

  Term.prototype.paste = function (text) {
    this.handler(bytesToBinaryString(encoder.encode(text)));
  };

  Term.prototype.pasteClipboard = async function () {
    if (!navigator.clipboard || !navigator.clipboard.readText) {
      this.writeln("Browser clipboard read is not available.");
      return;
    }
    const text = await navigator.clipboard.readText();
    if (text) {
      this.paste(text);
    }
    this.xterm.focus();
  };

  Term.prototype.copySelection = async function () {
    const text = this.xterm.getSelection();
    if (!text) {
      this.xterm.focus();
      return;
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      await navigator.clipboard.writeText(text);
    }
    this.xterm.focus();
  };

  window.Term = Term;
})();
