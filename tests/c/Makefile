# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
# Shell-free: `pwd` and `rm` are unavailable under mingw32-make on Windows.
ifeq ($(origin CC),default)
  ifeq ($(OS),Windows_NT)
    CC := gcc
  else
    CC := cc
  endif
endif

ROOT   := $(CURDIR)/../..
CFLAGS := -I$(ROOT)/include -O2 -Wall -Wextra -std=c11
LIB    := $(ROOT)/libUniBarCode.a
# libUniBarCode.a references libz via UniImage's PNG/DEFLATE codecs; a C
# consumer must supply libz itself (ubc_render_png pulls compress2 in).
# libm likewise: UniColor's conversions and UniVector's flattening call pow,
# exp, atan2 and friends. glibc keeps them in a separate library, so the link
# fails on Linux while macOS, which folds libm into libc, never noticed.
LIBS := -lz -lm

ifeq ($(OS),Windows_NT)
  BIN  := test_unibarcode.exe
  RUN  := $(BIN)
  RM_F := del /q
else
  BIN  := test_unibarcode
  RUN  := ./$(BIN)
  RM_F := rm -f
endif

.PHONY: all run clean
all: run
run: $(BIN)
	$(RUN)
$(BIN): test_unibarcode.c $(ROOT)/include/UniBarCode.h $(LIB)
	$(CC) $(CFLAGS) -o $(BIN) test_unibarcode.c $(LIB) $(LIBS)
# File target, not phony: `nimble ctest` already built the lib, don't redo it.
$(LIB):
	cd $(ROOT) && nimble clibStatic
clean:
	$(RM_F) $(BIN)
