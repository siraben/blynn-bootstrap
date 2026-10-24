import math
import os
import pathlib
import sys


src = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
block_size = 256 * 1024
zero_chunk = b"\0" * block_size
zero_chunk_path = None
data = src.read_bytes()
n_block = math.ceil(len(data) / block_size)
for i in range(n_block):
    path = out / f"blk{i:09d}.bin"
    chunk = data[i * block_size:(i + 1) * block_size]
    if len(chunk) < block_size:
        chunk += b"\0" * (block_size - len(chunk))
    if chunk == zero_chunk:
        if zero_chunk_path is None:
            path.write_bytes(chunk)
            zero_chunk_path = path
        else:
            os.link(zero_chunk_path, path)
    else:
        path.write_bytes(chunk)
(out / "blk.txt").write_text("{\n  block_size: 256,\n  n_block: %d,\n}\n" % n_block)
