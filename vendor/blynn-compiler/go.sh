#!/usr/bin/env bash

set -eux

# Where we put our binaries
mkdir -p bin

# Place to put generated source files
mkdir -p generated

# compile pack_blobs.c
M2-Planet --architecture x86 \
	-f M2libc/sys/types.h \
	-f M2libc/stddef.h \
	-f M2libc/x86/Linux/unistd.h \
	-f M2libc/stdlib.c \
	-f M2libc/x86/Linux/fcntl.h \
	-f M2libc/stdio.c \
	-f M2libc/bootstrappable.c \
	-f pack_blobs.c \
	--debug \
	-o bin/pack_blobs.M1

# Create dwarf stubs for pack_blobs
blood-elf -f bin/pack_blobs.M1 --little-endian --entry _start -o bin/pack_blobs-footer.M1

# Convert to hex2 linker format
M1 -f M2libc/x86/x86_defs.M1 \
	-f M2libc/x86/libc-full.M1 \
	-f bin/pack_blobs.M1 \
	-f bin/pack_blobs-footer.M1 \
	--little-endian \
	--architecture x86 \
	-o bin/pack_blobs.hex2

# Link into final static binary
hex2 -f M2libc/x86/ELF-x86-debug.hex2 \
	-f bin/pack_blobs.hex2 \
	--little-endian \
	--architecture x86 \
	--base-address 0x8048000 \
	-o bin/pack_blobs

# Build blobs
./bin/pack_blobs -f blob/parenthetically.source -o generated/parenthetically
./bin/pack_blobs -f blob/exponentially.source -o generated/exponentially
./bin/pack_blobs -f blob/practically.source -o generated/practically
./bin/pack_blobs -f blob/singularity.source -o generated/singularity_blob

# Compile to assembly vm.c
M2-Planet --architecture x86 \
	-f M2libc/sys/types.h \
	-f M2libc/stddef.h \
	-f M2libc/x86/Linux/unistd.h \
	-f M2libc/stdlib.c \
	-f M2libc/x86/Linux/fcntl.h \
	-f M2libc/stdio.c \
	-f M2libc/bootstrappable.c \
	-f vm.c \
	--debug \
	-o bin/vm.M1

# Create dwarf stubs for vm
blood-elf -f bin/vm.M1 --little-endian --entry _start -o bin/vm-footer.M1

# Convert to hex2 linker format
M1 -f M2libc/x86/x86_defs.M1 \
	-f M2libc/x86/libc-full.M1 \
	-f bin/vm.M1 \
	-f bin/vm-footer.M1 \
	--little-endian \
	--architecture x86 \
	-o bin/vm.hex2

# Link into final static binary
hex2 -f M2libc/x86/ELF-x86-debug.hex2 \
	-f bin/vm.hex2 \
	--little-endian \
	--architecture x86 \
	--base-address 0x8048000 \
	-o bin/vm

# Generate raw file needed
./bin/vm --raw blob/root -pb bootstrap -lf generated/parenthetically -o bin/raw_l
./bin/vm --raw bin/raw_l -pb generated/parenthetically -lf generated/exponentially -o bin/raw_m
./bin/vm --raw bin/raw_m -pb generated/exponentially -lf generated/practically -o bin/raw_n
./bin/vm --raw bin/raw_n -pb generated/practically -lf generated/singularity_blob -o bin/raw_o
./bin/vm --raw bin/raw_o -pb generated/singularity_blob -lf singularity -o bin/raw_p
./bin/vm --raw bin/raw_p -pb singularity -lf semantically -o bin/raw_q
./bin/vm --raw bin/raw_q -pb semantically -lf stringy -o bin/raw_r
./bin/vm --raw bin/raw_r -pb stringy -lf binary -o bin/raw_s
./bin/vm --raw bin/raw_s -pb binary -lf algebraically -o bin/raw_t
./bin/vm --raw bin/raw_t -pb algebraically -lf parity.hs -o bin/raw_u
./bin/vm --raw bin/raw_u -pb parity.hs -lf fixity.hs -o bin/raw_v
./bin/vm --raw bin/raw_v -pb fixity.hs -lf typically.hs -o bin/raw_w
./bin/vm --raw bin/raw_w -pb typically.hs -lf classy.hs -o bin/raw_x
./bin/vm --raw bin/raw_x -pb classy.hs -lf barely.hs -o bin/raw_y
./bin/vm --raw bin/raw_y -pb barely.hs -lf barely.hs -o bin/raw_z
./bin/vm -l bin/raw_z -lf barely.hs -o bin/raw

# Make lonely
./bin/vm -l bin/raw -lf effectively.hs --redo -lf lonely.hs -o generated/lonely_raw.txt

# Make patty
./bin/vm -f patty.hs --raw generated/lonely_raw.txt --rts_c run -o generated/patty_raw.txt

# Make guardedly
./bin/vm -f guardedly.hs --raw generated/patty_raw.txt --rts_c run -o generated/guardedly_raw.txt

# Make assembly
./bin/vm -f assembly.hs --raw generated/guardedly_raw.txt --rts_c run -o generated/assembly_raw.txt

# Make mutually
./bin/vm -f mutually.hs --foreign 2 --raw generated/assembly_raw.txt --rts_c run -o generated/mutually_raw.txt

# Make uniquely
./bin/vm -f uniquely.hs --foreign 2 --raw generated/mutually_raw.txt --rts_c run -o generated/uniquely_raw.txt

# Make virtually
./bin/vm -f virtually.hs --foreign 2 --raw generated/uniquely_raw.txt --rts_c run -o generated/virtually_raw.txt

# Make marginally
./bin/vm -f marginally.hs --foreign 2 --raw generated/virtually_raw.txt --rts_c run -o generated/marginally.c
M2-Planet --architecture x86 \
	-f M2libc/sys/types.h \
	-f M2libc/stddef.h \
	-f M2libc/x86/Linux/unistd.h \
	-f M2libc/stdlib.c \
	-f M2libc/x86/Linux/fcntl.h \
	-f M2libc/stdio.c \
	-f M2libc/bootstrappable.c \
	-f generated/marginally.c \
	--debug \
	-o bin/marginally.M1

blood-elf -f bin/marginally.M1 --little-endian --entry _start -o bin/marginally-footer.M1

M1 -f M2libc/x86/x86_defs.M1 \
	-f M2libc/x86/libc-full.M1 \
	-f bin/marginally.M1 \
	-f bin/marginally-footer.M1 \
	--little-endian \
	--architecture x86 \
	-o bin/marginally.hex2

hex2 -f M2libc/x86/ELF-x86-debug.hex2 \
	-f bin/marginally.hex2 \
	--little-endian \
	--architecture x86 \
	--base-address 0x8048000 \
	-o bin/marginally

# Make methodically
./bin/marginally methodically.hs generated/methodically.c
M2-Planet --architecture x86 \
	-f M2libc/sys/types.h \
	-f M2libc/stddef.h \
	-f M2libc/x86/Linux/unistd.h \
	-f M2libc/stdlib.c \
	-f M2libc/x86/Linux/fcntl.h \
	-f M2libc/stdio.c \
	-f M2libc/bootstrappable.c \
	-f generated/methodically.c \
	--debug \
	-o bin/methodically.M1

blood-elf -f bin/methodically.M1 --little-endian --entry _start -o bin/methodically-footer.M1

M1 -f M2libc/x86/x86_defs.M1 \
	-f M2libc/x86/libc-full.M1 \
	-f bin/methodically.M1 \
	-f bin/methodically-footer.M1 \
	--little-endian \
	--architecture x86 \
	-o bin/methodically.hex2

hex2 -f M2libc/x86/ELF-x86-debug.hex2 \
	-f bin/methodically.hex2 \
	--little-endian \
	--architecture x86 \
	--base-address 0x8048000 \
	-o bin/methodically

# Make crossly
./bin/methodically crossly.hs generated/crossly.c
M2-Planet --architecture x86 \
	-f M2libc/sys/types.h \
	-f M2libc/stddef.h \
	-f M2libc/x86/Linux/unistd.h \
	-f M2libc/stdlib.c \
	-f M2libc/x86/Linux/fcntl.h \
	-f M2libc/stdio.c \
	-f M2libc/bootstrappable.c \
	-f generated/crossly.c \
	--debug \
	-o bin/crossly.M1

blood-elf -f bin/crossly.M1 --little-endian --entry _start -o bin/crossly-footer.M1

M1 -f M2libc/x86/x86_defs.M1 \
	-f M2libc/x86/libc-full.M1 \
	-f bin/crossly.M1 \
	-f bin/crossly-footer.M1 \
	--little-endian \
	--architecture x86 \
	-o bin/crossly.hex2

hex2 -f M2libc/x86/ELF-x86-debug.hex2 \
	-f bin/crossly.hex2 \
	--little-endian \
	--architecture x86 \
	--base-address 0x8048000 \
	-o bin/crossly

# Make precisely
./bin/crossly precisely.hs generated/precisely.c
M2-Planet --architecture x86 \
	-f M2libc/sys/types.h \
	-f M2libc/stddef.h \
	-f M2libc/x86/Linux/unistd.h \
	-f M2libc/stdlib.c \
	-f M2libc/x86/Linux/fcntl.h \
	-f M2libc/stdio.c \
	-f M2libc/bootstrappable.c \
	-f generated/precisely.c \
	--debug \
	-o bin/precisely.M1

blood-elf -f bin/precisely.M1 --little-endian --entry _start -o bin/precisely-footer.M1

M1 -f M2libc/x86/x86_defs.M1 \
	-f M2libc/x86/libc-full.M1 \
	-f bin/precisely.M1 \
	-f bin/precisely-footer.M1 \
	--little-endian \
	--architecture x86 \
	-o bin/precisely.hex2

hex2 -f M2libc/x86/ELF-x86-debug.hex2 \
	-f bin/precisely.hex2 \
	--little-endian \
	--architecture x86 \
	--base-address 0x8048000 \
	-o bin/precisely
