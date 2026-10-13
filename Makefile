#Date: 11-25-23
#Author: David Kittell
#Revision: 1.1  (10-06-26, with Claude: module dependencies, -J, safe
#                link and clean; see the NOTES blocks below)
#Revision: 1.2  (10-13-26, with Claude: build date and git version
#                recorded in src/modules/build_mod.f95)
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
	-finit-integer=-999999 -fconvert=little-endian -fimplicit-none
OMPFLAGS = -fopenmp

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
############################################################
src/modules/shock_mod.o: src/modules/bit_mod.o
src/modules/deck_mod.o:  src/modules/shock_mod.o src/modules/bit_mod.o

############################################################
###  NOTES: files a RUN leaves behind (not build products).
###  'make cleanrun' removes only these and keeps the objects
###  and bin/bitwhiz, so the next run needs no rebuild.
###  Add each new output type here as bitwhiz learns to
###  write it (tracers, snapshots, run log, ...).
###  The decks and README in input/ are never touched.
############################################################
RUN_FILES = *.heartbeat input/*.heartbeat input/*.bmp

cleanrun:
	rm -f $(RUN_FILES)

############################################################
###  NOTES: 'make clean' removes the build products AND the
###  run outputs, for a fresh start.
############################################################
clean: cleanrun
	rm -f $(EXECS) $(MOD_OBJS) $(LIB_OBJS) $(BIN) $(MOD_FILS)
	rm -f $(BUILD_SRC) $(BUILD_OBJ) src/modules/build.mod
	rm -f bitwhiz *.mod

############################################################
###  NOTES: bitmaps in the top folder are kept by both
###  targets above (e.g. a figure you want to keep); remove
###  them on purpose with 'make cleanbmp'.
############################################################
cleanbmp:
	rm -f *.bmp

.f95.o:
	$(FC) $(INCLUDES) -c $(FCFLAGS) $(OMPFLAGS) $< -o $@

.PHONY : bitwhiz clean cleanrun cleanbmp FORCE
# End of the makefile
