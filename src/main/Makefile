# Set up the path to include Fortran modules
INCLUDE_PATH = ../modules
INCLUDES = -I$(INCLUDE_PATH)

# The compiler
FC = gfortran

# The flags
FCFLAGS = -O3

# Start of the makefile (make object files only and do not link them)
SRCS = maincode.f95 bmpmaker.f95 bmpreader.f95
OBJS = $(SRCS:.f95=.o)
EXECS = server

server: $(OBJS) $(MOD_OBJS)

# Rules
maincode.o: maincode.f95
	$(FC) $(INCLUDES) -c $(FCFLAGS) maincode.f95
bmpmaker.o: bmpmaker.f95
	$(FC) $(INCLUDES) -c $(FCFLAGS) bmpmaker.f95
bmpreader.o: bmpreader.f95
	$(FC) $(INCLUDES) -c $(FCFLAGS) bmpreader.f95

# Extra targets.
clean:
	@rm -f $(EXECS) $(OBJS)

.PHONY: default clean
#End of the makefile
