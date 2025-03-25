#Date: 11-25-23
#Author: David Kittell
#Revision: 1.0
#
# This is a bare bones Makefile system for gfortran.
#
SHELL := /bin/bash

include ./src/objslist

# The compiler
FC = gfortran

# The flags
FCFLAGS = -O3

# Set up path to Fortran module files.
INCLUDE_PATH = ./src/modules
INCLUDES = -I$(INCLUDE_PATH)

.SUFFIXES: .o .mod .f95

EXECS = ./bin/bitwhiz

############################################################
###  NOTES: this simple target works, because the modules
###  are compiled first. I.E., MOD_OBJS is the first set
###  of objects to appear in the target.
############################################################

# Targets
bitwhiz: $(MOD_OBJS) $(LIB_OBJS) $(BIN)
	$(FC) $(INCLUDES) -o bitwhiz $(BIN) $(MOD_OBJS) \
		$(LIB_OBJS); \
	mv bitwhiz ./bin/bitwhiz ; \
	if [ -f bits.mod ]; then \
	 echo "cleaning up loose module files..."; \
	 mv *.mod $(INCLUDE_PATH)/; \
	fi;

clean:
	rm $(EXECS) $(MOD_OBJS) $(LIB_OBJS) $(BIN) ; \
	rm $(MOD_FILS) ; \
	rm bitwhiz *.mod *.bmp;

.f95.o:
	$(FC) $(INCLUDES) -c $(FCFLAGS) $< -o $@

.PHONY : bitwhiz
# End of the makefile
