#!/usr/bin/env bash

set -eux

# Where we put our binaries
mkdir -p bin

# Place to put generated source files
mkdir -p generated

M2_ARCH=${M2_ARCH:-x86}
M2_OS=${M2_OS:-Linux}

compile_m2() {
	M2-Mesoplanet --operating-system "$M2_OS" --architecture "$M2_ARCH" -f "$1" -o "$2"
	chmod 555 "$2"
}

compile_m2 pack_blobs.c bin/pack_blobs

# Build blobs
./bin/pack_blobs -f blob/parenthetically.source -o generated/parenthetically
./bin/pack_blobs -f blob/exponentially.source -o generated/exponentially
./bin/pack_blobs -f blob/practically.source -o generated/practically
./bin/pack_blobs -f blob/singularity.source -o generated/singularity_blob

compile_m2 vm.c bin/vm

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

./bin/vm -f marginally.hs --foreign 2 --raw generated/virtually_raw.txt --rts_c run -o generated/marginally.c
compile_m2 generated/marginally.c bin/marginally

./bin/marginally methodically.hs generated/methodically.c
compile_m2 generated/methodically.c bin/methodically

./bin/methodically crossly.hs generated/crossly.c
compile_m2 generated/crossly.c bin/crossly

./bin/crossly precisely.hs generated/precisely.c
compile_m2 generated/precisely.c bin/precisely
