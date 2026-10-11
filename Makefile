#Date: 11-25-23
#Author: David Kittell
#Revision: 1.1  (10-06-26, with Claude: module dependencies, -J, safe
#                link and clean; see the NOTES blocks below)
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

# Targets
############################################################
###  NOTES: the target is the real file ./bin/bitwhiz, so
###  'make' with nothing changed does nothing. The link
###  writes straight into ./bin, and if it fails, make
###  stops with an error (no stale executable left behind).
############################################################
bitwhiz: $(EXECS)

$(EXECS): $(MOD_OBJS) $(LIB_OBJS) $(BIN)
	@mkdir -p ./bin
	$(FC) $(OMPFLAGS) $(INCLUDES) -o $(EXECS) $(BIN) $(MOD_OBJS) $(LIB_OBJS)

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

clean:
	rm -f $(EXECS) $(MOD_OBJS) $(LIB_OBJS) $(BIN) $(MOD_FILS)
	rm -f bitwhiz *.mod

############################################################
###  NOTES: images are outputs, not build products, so they
###  have their own target ('make cleanbmp'); 'make clean'
###  no longer deletes every .bmp in the top folder.
############################################################
cleanbmp:
	rm -f *.bmp

.f95.o:
	$(FC) $(INCLUDES) -c $(FCFLAGS) $(OMPFLAGS) $< -o $@

.PHONY : bitwhiz clean cleanbmp
# End of the makefile
