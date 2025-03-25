# Set up the path to include Fortran modules
INCLUDE_PATH = ../modules
INCLUDES = -I$(INCLUDE_PATH)

# The compiler
FC = gfortran

# The flags
FCFLAGS = -O3

# Start of the makefile (make object files only and do not link them)
SRCS = random.f95 timestamp.f95
OBJS = $(SRCS:.f95=.o)
EXECS = server

server: $(OBJS) $(MOD_OBJS)

# Rules
random.o: random.f95
	$(FC) $(INCLUDES) -c $(FCFLAGS) random.f95
timestamp.o: timestamp.f95
	$(FC) $(INCLUDES) -c $(FCFLAGS) timestamp.f95

# Extra targets.
clean:
	@rm -f $(EXECS) $(OBJS)

.PHONY: default clean
#End of the makefile
