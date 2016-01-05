# Copyright (c) 2011 The LevelDB Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file. See the AUTHORS file for names of contributors.

# Inherit some settings from environment variables, if available
INSTALL_PATH ?= $(CURDIR)

#-----------------------------------------------
# Uncomment exactly one of the lines labelled (A), (B), and (C) below
# to switch between compilation modes.
#  NOTE: targets "debug" and "prof" provide same functionality

OPT ?= -O2 -g -DNDEBUG    # (A) Production use (optimized mode)
# OPT ?= -g2              # (B) Debug mode, w/ full line-level debugging symbols
# OPT ?= -O2 -g2 -DNDEBUG # (C) Profiling mode: opt, but w/debugging symbols
#-----------------------------------------------

# detect what platform we're building on
ifeq ($(wildcard build_config.mk),)
$(shell ./build_detect_platform build_config.mk)
endif
# this file is generated by the previous line to set build flags and sources
include build_config.mk

CFLAGS += -I. -I./include $(PLATFORM_CCFLAGS) $(OPT)
CXXFLAGS += -I. -I./include $(PLATFORM_CXXFLAGS) $(OPT)

LDFLAGS += $(PLATFORM_LDFLAGS)

LIBOBJECTS := $(SOURCES:.cc=.o)
LIBOBJECTS += util/lz4.o
MEMENVOBJECTS = $(MEMENV_SOURCES:.cc=.o)
DEPEND := $(SOURCES:.cc=.d)

TESTUTIL = ./util/testutil.o
TESTHARNESS = ./util/testharness.o $(TESTUTIL)

TESTS = \
	arena_test \
	bloom_test \
	c_test \
	cache_test \
	cache2_test \
	coding_test \
	corruption_test \
	crc32c_test \
	db_test \
	dbformat_test \
	env_test \
	filename_test \
	filter_block_test \
	flexcache_test \
	log_test \
	memenv_test \
	perf_count_test \
	skiplist_test \
	table_test \
	version_edit_test \
	version_set_test \
	write_batch_test

TOOLS = \
	leveldb_repair \
	perf_dump \
	sst_rewrite \
	sst_scan

PROGRAMS = db_bench $(TESTS) $(TOOLS)
BENCHMARKS = db_bench_sqlite3 db_bench_tree_db

LIBRARY = libleveldb.a
MEMENVLIBRARY = libmemenv.a

#
# static link leveldb to tools to simplify platform usage (if Linux)
#
ifeq ($(PLATFORM),OS_LINUX)
LEVEL_LDFLAGS := -L . -l:$(LIBRARY)
else
LEVEL_LDFLAGS := -L . -lleveldb
endif

default: all

# Should we build shared libraries?
ifneq ($(PLATFORM_SHARED_EXT),)

ifneq ($(PLATFORM_SHARED_VERSIONED),true)
SHARED1 = libleveldb.$(PLATFORM_SHARED_EXT)
SHARED2 = $(SHARED1)
SHARED3 = $(SHARED1)
SHARED = $(SHARED1)
else
# Update db.h if you change these.
SHARED_MAJOR = 1
SHARED_MINOR = 9
SHARED1 = libleveldb.$(PLATFORM_SHARED_EXT)
SHARED2 = $(SHARED1).$(SHARED_MAJOR)
SHARED3 = $(SHARED1).$(SHARED_MAJOR).$(SHARED_MINOR)
SHARED = $(SHARED1) $(SHARED2) $(SHARED3)
$(SHARED1): $(SHARED3)
	ln -fs $(SHARED3) $(SHARED1)
$(SHARED2): $(SHARED3)
	ln -fs $(SHARED3) $(SHARED2)
endif

$(SHARED3): $(LIBOBJECTS)
	$(CXX) $(CXXFLAGS) $(PLATFORM_SHARED_CFLAGS) $(LIBOBJECTS) -o $(SHARED3) $(LDFLAGS) $(PLATFORM_SHARED_LDFLAGS)$(SHARED2)

endif  # PLATFORM_SHARED_EXT

all: $(SHARED) $(LIBRARY)

test check: all $(PROGRAMS) $(TESTS)
	for t in $(TESTS); do echo "***** Running $$t"; ./$$t || exit 1; done

tools: all $(TOOLS)

#
# command line targets:  debug and prof
#  just like
ifneq ($(filter debug,$(MAKECMDGOALS)),)
OPT := -g2              # (B) Debug mode, w/ full line-level debugging symbols
debug: all
endif

ifneq ($(filter prof,$(MAKECMDGOALS)),)
OPT := -O2 -g2 -DNDEBUG # (C) Profiling mode: opt, but w/debugging symbols
prof: all
MK_PROF := 1
endif


clean:
	-rm -f $(PROGRAMS) $(BENCHMARKS) $(LIBRARY) $(SHARED) $(MEMENVLIBRARY) */*.o */*/*.o */*.d */*/*.d ios-x86/*/*.o ios-arm/*/*.o build_config.mk include/leveldb/ldb_config.h
	-rm -rf ios-x86/* ios-arm/* *.dSYM


$(LIBRARY): $(LIBOBJECTS)
	rm -f $@
	$(AR) -rs $@ $(LIBOBJECTS)

#
# all tools, programs, and tests depend upon the static library
$(TESTS) $(PROGRAMS) $(TOOLS) : $(LIBRARY)

#
# all tests depend upon the test harness
$(TESTS) : $(TESTHARNESS)

#
# tools, programs, and tests will compile to the root directory
#  but their .cc source file will be in one of the following subdirectories
vpath %.cc db:table:util

# special case for c_test
vpath %.c db

db_bench: db/db_bench.o $(LIBRARY) $(TESTUTIL)
	$(CXX) $(CXXFLAGS) $(PLATFORM_SHARED_CFLAGS) $< $(TESTUTIL) -o $@  $(LEVEL_LDFLAGS) $(LDFLAGS)

db_bench_sqlite3: doc/bench/db_bench_sqlite3.o $(LIBRARY) $(TESTUTIL)

db_bench_tree_db: doc/bench/db_bench_tree_db.o $(LIBRARY) $(TESTUTIL)


#
# build line taken from lz4 makefile
#
util/lz4.o: util/lz4.c util/lz4.h
	$(CC) $(CFLAGS) $(PLATFORM_SHARED_CFLAGS) -O3 -std=c99 -Wall -Wextra -Wundef -Wshadow -Wcast-qual -Wcast-align -Wstrict-prototypes -pedantic -DLZ4_VERSION=\"r130\"  -c util/lz4.c -o util/lz4.o

#
# memory env
#
$(MEMENVLIBRARY) : $(MEMENVOBJECTS)
	rm -f $@
	$(AR) -rs $@ $(MEMENVOBJECTS)

memenv_test : helpers/memenv/memenv_test.o $(MEMENVLIBRARY) $(LIBRARY) $(TESTHARNESS)
	$(CXX) helpers/memenv/memenv_test.o $(MEMENVLIBRARY) $(LIBRARY) $(TESTHARNESS) -o $@ $(LDFLAGS)

#
# IOS build
#
ifeq ($(PLATFORM), IOS)
# For iOS, create universal object files to be used on both the simulator and
# a device.
PLATFORMSROOT=/Applications/Xcode.app/Contents/Developer/Platforms
SIMULATORROOT=$(PLATFORMSROOT)/iPhoneSimulator.platform/Developer
DEVICEROOT=$(PLATFORMSROOT)/iPhoneOS.platform/Developer
IOSVERSION=$(shell defaults read $(PLATFORMSROOT)/iPhoneOS.platform/version CFBundleShortVersionString)

.cc.o:
	mkdir -p ios-x86/$(dir $@)
	$(SIMULATORROOT)/usr/bin/$(CXX) $(CXXFLAGS) -isysroot $(SIMULATORROOT)/SDKs/iPhoneSimulator$(IOSVERSION).sdk -arch i686 -c $< -o ios-x86/$@
	mkdir -p ios-arm/$(dir $@)
	$(DEVICEROOT)/usr/bin/$(CXX) $(CXXFLAGS) -isysroot $(DEVICEROOT)/SDKs/iPhoneOS$(IOSVERSION).sdk -arch armv6 -arch armv7 -c $< -o ios-arm/$@
	lipo ios-x86/$@ ios-arm/$@ -create -output $@

.c.o:
	mkdir -p ios-x86/$(dir $@)
	$(SIMULATORROOT)/usr/bin/$(CC) $(CFLAGS) -isysroot $(SIMULATORROOT)/SDKs/iPhoneSimulator$(IOSVERSION).sdk -arch i686 -c $< -o ios-x86/$@
	mkdir -p ios-arm/$(dir $@)
	$(DEVICEROOT)/usr/bin/$(CC) $(CFLAGS) -isysroot $(DEVICEROOT)/SDKs/iPhoneOS$(IOSVERSION).sdk -arch armv6 -arch armv7 -c $< -o ios-arm/$@
	lipo ios-x86/$@ ios-arm/$@ -create -output $@

else
#
# build for everything NOT IOS
#
.cc.o:
	$(CXX) $(CXXFLAGS) $(PLATFORM_SHARED_CFLAGS) -c $< -o $@

.c.o:
	$(CC) $(CFLAGS) $(PLATFORM_SHARED_CFLAGS) -c $< -o $@

%.d: %.cc
	@echo -- Creating dependency file for $<
	$(CC) $(CFLAGS) $(PLATFORM_SHARED_CFLAGS) -MM -E -MT $(basename $@).d -MT $(basename $@).o -MF $@ $<
	@echo $(basename $@).o: $(basename $@).d >>$@

# generic build for command line tests
%: %.cc
	$(CXX) $(CXXFLAGS) $(PLATFORM_SHARED_CFLAGS) $< $(TESTHARNESS) -o $@ $(LEVEL_LDFLAGS) $(LDFLAGS)

%: db/%.c
	$(CXX) $(CXXFLAGS) $(PLATFORM_SHARED_CFLAGS) $< $(TESTHARNESS) -o $@ $(LEVEL_LDFLAGS) $(LDFLAGS)

# for tools, omits test harness
%: tools/%.cc
	$(CXX) $(CXXFLAGS) $(PLATFORM_SHARED_CFLAGS) $< -o $@ $(LEVEL_LDFLAGS) $(LDFLAGS)

endif

#
# load dependency files
#
ifeq ($(filter tar clean allclean distclean,$(MAKECMDGOALS)),)
-include $(DEPEND)
endif
