#Date: 11-25-23
#Author: David Kittell
#Revision: 1.1  (10-06-26, with Claude: module dependencies, -J, safe
#                link and clean; see the NOTES blocks below)
#Revision: 1.2  (10-13-26, with Claude: build date and git version
#                recorded in src/modules/build_mod.f95)
#Revision: 1.3  (10-13-26, with Claude: 'make test')
#Revision: 1.4  (10-14-26, with Claude: eos module, EOS unit test)
#Revision: 1.5  (10-15-26, with Claude: av module, the time loop)
#Revision: 1.6  (10-15-26, with Claude: OpenMP tests in 'make test')
#Revision: 1.7  (10-15-26, with Claude: -ffp-contract=off, same answer
#                on x86 and arm64; see the NOTES at FCFLAGS)
#Revision: 1.8  (10-15-26, with Claude: trace module, tracer file)
#Revision: 1.9  (10-19-26, with Claude: rs module, method RS)
#Revision: 1.10 (10-20-26, with Claude: 'cleanrun' renamed 'tidy' and
#                'cleanbmp' renamed 'bmpclean', so no target name is
#                the start of another; see the NOTES at 'tidy')
#Revision: 1.11 (10-20-26, with Claude: 'make release', an optimized
#                build in build/release, checked against the debug
#                build; see the NOTES at RFLAGS and at 'release')
#Revision: 1.12 (10-20-26, with Claude: hist module, the history file;
#                its tests in 'make test' and 'make release')
#Revision: 1.13 (10-20-26, with Claude: pics module, the pictures;
#                plots_only tests in run_hist_tests.sh)
#Revision: 1.14 (10-20-26, with Claude: draw_xt and draw_trace; 'tidy'
#                removes the run's pictures; 'clean' removes the
#                macOS debug-symbol folders, bin/*.dSYM)
#
# This is a bare bones Makefile system for gfortran.
#
SHELL := /bin/bash

include ./src/objslist

# The compiler
FC = gfortran

# The flags
FCFLAGS = -std=f2018 -Wall -Wextra -Wno-implicit-interface -Wsurprising \
	-Waliasing -Wampersand -Wconversion -Wcharacter-truncation \
	-Wline-truncation -fcheck=all -fbacktrace -g -O0 \
	-ffpe-trap=invalid,zero,overflow -finit-real=snan \
	-finit-integer=-999999 -fconvert=little-endian -fimplicit-none \
	-ffp-contract=off
OMPFLAGS = -fopenmp

# The release flags ('make release')
RFLAGS = -std=f2018 -O2 -fimplicit-none -fconvert=little-endian \
	-ffp-contract=off

############################################################
###  NOTES: RFLAGS are for 'make release', the executable to
###  hand out or host. They keep what decides the ANSWER
###  (-std, -fimplicit-none, -fconvert, -ffp-contract=off) and
###  drop what only helps find bugs: the run-time checks
###  (-fcheck=all), the floating-point traps, the NaN and
###  -999999 fills, -g, and the warnings (the debug build
###  already shows them, from the same source). -O2 does not
###  reorder arithmetic, so the release build must compute the
###  same bits as the debug build; 'make release' checks that
###  it does. Without traps, a NaN is still caught: the
###  heartbeat's finite check stops the run (maincode,
###  heartbeat_line). The rule against -ffast-math and -Ofast
###  below holds here too.
############################################################

############################################################
###  NOTES: -ffp-contract=off keeps the compiler from fusing
###  a*b + c into one "fused multiply-add" instruction. On
###  arm64 (Apple M, AWS Graviton, ...) gcc fuses by default;
###  on plain x86-64 it can not. A fused result is rounded
###  once instead of twice, so the two machines would differ
###  in the last digits (measured: ~3e-11 km/s on the class
###  problem). With fusing off, and with the solver using only
###  + - * / and sqrt (all exactly rounded by IEEE 754), every
###  machine should compute the SAME bits. Cost: a few percent
###  on arm64, nothing on x86. Never add -ffast-math or -Ofast:
###  they reorder sums, drop NaN checks and break both this and
###  the bit-for-bit OpenMP tests.
############################################################

# Set up path to Fortran module files.
############################################################
###  NOTES: -J writes every .mod straight into src/modules,
###  so no loose .mod files land in the top folder and the
###  old 'mv *.mod' clean-up step is no longer needed.
############################################################
INCLUDE_PATH = ./src/modules
INCLUDES = -I$(INCLUDE_PATH) -J$(INCLUDE_PATH)

.SUFFIXES: .o .mod .f95

EXECS = ./bin/bitwhiz

# The build record (when, and from which git version); see the NOTES
# at the BUILD_SRC rule. Defined here, before any rule that uses it.
BUILD_SRC = src/modules/build_mod.f95
BUILD_OBJ = src/modules/build_mod.o

# Targets
############################################################
###  NOTES: the target is the real file ./bin/bitwhiz. The
###  link writes straight into ./bin, and if it fails, make
###  stops with an error (no stale executable left behind).
###  With nothing changed, 'make' only refreshes the build
###  record (see BUILD_SRC below) and relinks.
############################################################
bitwhiz: $(EXECS)

$(EXECS): $(MOD_OBJS) $(LIB_OBJS) $(BIN) $(BUILD_OBJ)
	@mkdir -p ./bin
	$(FC) $(OMPFLAGS) $(INCLUDES) -o $(EXECS) $(BIN) $(MOD_OBJS) \
		$(LIB_OBJS) $(BUILD_OBJ)

############################################################
###  NOTES: build_mod.f95 records WHEN and FROM WHICH git
###  version bin/bitwhiz was built; the banner and the
###  heartbeat print it. It is rewritten on every 'make'
###  (FORCE), so 'make' always recompiles this one small
###  file and relinks, about a second. It is NOT in
###  MOD_OBJS, so nothing else recompiles because of it;
###  maincode only needs it to exist first, which is what
###  the order-only rule ('|') says.
############################################################
$(BUILD_SRC): FORCE
	@sh src/utils/make_build_info.sh $(BUILD_SRC)

$(BUILD_OBJ): $(BUILD_SRC)

$(BIN): | $(BUILD_OBJ)

FORCE:

############################################################
###  NOTES: every non-module object depends on the module
###  objects. Fortran copies parameter values into each file
###  that uses them, so editing a module must recompile its
###  users. This one line also makes 'make -j' safe.
############################################################
$(LIB_OBJS) $(BIN): $(MOD_OBJS)

############################################################
###  NOTES: modules that USE other modules must be built
###  after them. Plain 'make' already follows the order in
###  objslist; these lines make 'make -j' safe too.
###  The list is written once, as MOD_ORDER, and used for the
###  debug objects here and the release objects in RDIR (the
###  argument $(1) is the folder put in front of every name).
############################################################
define MOD_ORDER
$(1)src/modules/shock_mod.o: $(1)src/modules/bit_mod.o
$(1)src/modules/deck_mod.o:  $(1)src/modules/shock_mod.o $(1)src/modules/bit_mod.o
$(1)src/modules/eos_mod.o:   $(1)src/modules/bit_mod.o
$(1)src/modules/av_mod.o:    $(1)src/modules/eos_mod.o $(1)src/modules/shock_mod.o \
                             $(1)src/modules/bit_mod.o
$(1)src/modules/trace_mod.o: $(1)src/modules/shock_mod.o $(1)src/modules/bit_mod.o
$(1)src/modules/hist_mod.o:  $(1)src/modules/shock_mod.o $(1)src/modules/bit_mod.o
$(1)src/modules/pics_mod.o:  $(1)src/modules/hist_mod.o $(1)src/modules/deck_mod.o \
                             $(1)src/modules/shock_mod.o $(1)src/modules/bit_mod.o
$(1)src/modules/rs_mod.o:    $(1)src/modules/av_mod.o $(1)src/modules/eos_mod.o \
                             $(1)src/modules/shock_mod.o $(1)src/modules/bit_mod.o
endef
$(eval $(call MOD_ORDER,))

############################################################
###  NOTES: 'make test' builds bitwhiz and the unit tests if
###  needed, then runs the unit tests (one program each in
###  tests/, exit status 0 = pass), the deck reader tests
###  (tests/run_deck_tests.sh) and the OpenMP tests
###  (tests/run_omp_tests.sh: 2, 3, 4 and 8 threads, as many
###  as there are processors, must print exactly what 1 thread
###  prints) and the history file tests (tests/run_hist_tests.sh:
###  bin/test_hist checks each run's <title>.hist against the
###  format in input/README.md, section 9, and against the tracer
###  file). Every check must pass; make stops with an error
###  at the first one that fails. Run it before every commit.
###  A new unit test: add its program to UNIT_TESTS and a
###  line to the 'test' recipe; the pattern rule builds it.
###  It links every module AND the library objects: module
###  pics calls the drawing routines (src/drawings), which
###  call bmpmaker and the colormaps.
############################################################
UNIT_TESTS = ./bin/test_eos ./bin/test_hist

./bin/test_%: tests/test_%.f95 $(MOD_OBJS) $(LIB_OBJS)
	@mkdir -p ./bin
	$(FC) $(INCLUDES) $(FCFLAGS) $(OMPFLAGS) -o $@ $< $(MOD_OBJS) $(LIB_OBJS)

test: $(EXECS) $(UNIT_TESTS)
	./bin/test_eos
	BIN=$(EXECS) ./tests/run_deck_tests.sh
	BIN=$(EXECS) ./tests/run_omp_tests.sh
	BIN=$(EXECS) ./tests/run_hist_tests.sh

############################################################
###  NOTES: 'make release' builds the optimized executable,
###  ./bin/bitwhiz_release, with RFLAGS, in its own folder
###  (RDIR: objects and .mod files under build/release, which
###  git ignores). The debug build in src/ is never touched,
###  so 'make' and 'make release' can be used in any order
###  and neither one recompiles the other's files.
###  It then checks the release build: the deck, OpenMP and
###  history file tests on it, and tests/run_release_tests.sh, which
###  runs the decks on both builds and requires them to print
###  the same results, heartbeat, tracer rows and history
###  frames, bit for bit (the debug build is made first if
###  needed). Any failure
###  stops make with an error. To hand it out, copy it under
###  any name; its banner and heartbeat say "optimized" and
###  record its flags and git version.
############################################################
RDIR     = build/release
REL_EXEC = ./bin/bitwhiz_release
R_INCS   = -I$(RDIR)/mod -J$(RDIR)/mod
R_MODS   = $(addprefix $(RDIR)/,$(MOD_OBJS))
R_LIBS   = $(addprefix $(RDIR)/,$(LIB_OBJS))
R_BIN    = $(addprefix $(RDIR)/,$(BIN))
R_BUILD  = $(RDIR)/$(BUILD_OBJ)

release: $(REL_EXEC) $(EXECS) $(UNIT_TESTS)
	BIN=$(REL_EXEC) ./tests/run_deck_tests.sh
	BIN=$(REL_EXEC) ./tests/run_omp_tests.sh
	BIN=$(REL_EXEC) ./tests/run_hist_tests.sh
	DEBUG=$(EXECS) RELEASE=$(REL_EXEC) ./tests/run_release_tests.sh

$(REL_EXEC): $(R_MODS) $(R_LIBS) $(R_BIN) $(R_BUILD)
	@mkdir -p ./bin
	$(FC) $(OMPFLAGS) -o $(REL_EXEC) $(R_BIN) $(R_MODS) $(R_LIBS) \
		$(R_BUILD)

$(RDIR)/%.o: %.f95
	@mkdir -p $(dir $@) $(RDIR)/mod
	$(FC) $(R_INCS) -c $(RFLAGS) $(OMPFLAGS) $< -o $@

$(R_BUILD): $(BUILD_SRC)
$(R_BIN): | $(R_BUILD)
$(R_LIBS) $(R_BIN): $(R_MODS)
$(eval $(call MOD_ORDER,$(RDIR)/))

############################################################
###  NOTES: files a RUN leaves behind (not build products).
###  'make tidy' removes only these and keeps the objects
###  and bin/bitwhiz, so the next run needs no rebuild.
###  Add each new output type here as bitwhiz learns to
###  write it (tracers, snapshots, run log, ...).
###  The decks and README in input/ are never touched.
###  A run's pictures are named <title>.xt_u.bmp,
###  <title>.xt_p.bmp and <title>.tr_<tracer>.bmp, so only
###  those bitmaps go here; any other .bmp in the top folder
###  is kept (see bmpclean below).
############################################################
RUN_FILES = *.heartbeat input/*.heartbeat *.tracers.csv \
            input/*.tracers.csv *.hist input/*.hist input/*.bmp \
            *.xt_u.bmp *.xt_p.bmp *.tr_*.bmp

############################################################
###  NOTES: target names. No target name is the start of
###  another, so a name typed short fails ('No rule to make
###  target') instead of running a different target. The
###  old names 'cleanrun' and 'cleanbmp' both began with
###  'clean': stopping early removed the whole build. To
###  see what a target would do without doing it:
###      make -n clean
############################################################
tidy:
	rm -f $(RUN_FILES)

############################################################
###  NOTES: 'make clean' removes the build products (debug
###  and release) AND the run outputs, for a fresh start.
###  On macOS, linking with -g also writes a debug-symbol
###  folder next to each program (bin/test_eos.dSYM, ...);
###  those go too.
############################################################
clean: tidy
	rm -f $(EXECS) $(MOD_OBJS) $(LIB_OBJS) $(BIN) $(MOD_FILS)
	rm -f $(BUILD_SRC) $(BUILD_OBJ) src/modules/build.mod
	rm -f bitwhiz *.mod $(UNIT_TESTS)
	rm -rf $(RDIR) $(REL_EXEC)
	rm -rf ./bin/*.dSYM

############################################################
###  NOTES: bitmaps in the top folder are kept by both
###  targets above (e.g. a figure you want to keep), except
###  a run's own pictures (RUN_FILES); remove the rest on
###  purpose with 'make bmpclean'.
############################################################
bmpclean:
	rm -f *.bmp

.f95.o:
	$(FC) $(INCLUDES) -c $(FCFLAGS) $(OMPFLAGS) $< -o $@

.PHONY : bitwhiz test release clean tidy bmpclean FORCE
# End of the makefile
