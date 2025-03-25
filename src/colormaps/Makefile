# Set up the path to include Fortran modules
INCLUDE_PATH = ../modules
INCLUDES = -I$(INCLUDE_PATH)

# The compiler
FC = gfortran

# The flags
FCFLAGS = -O3

# Start of the makefile (make object files only and do not link them)
SRCS = cmap_grayscale.f95 cmap_plasma.f95 cmap_viridis.f95 \
	cmap_inferno.f95 cmap_blackbody.f95 cmap_kindlmann.f95 \
	cmap_extendedkindlmann.f95 cmap_smoothcoolwarm.f95 \
	cmap_bentcoolwarm.f95
OBJS = $(SRCS:.f95=.o)
EXECS = server

server: $(OBJS) $(MOD_OBJS)

# Rules
cmap_grayscale.o: cmap_grayscale.f95
	$(FC) $(INCLUDES) -c $(FCFLAGS) cmap_grayscale.f95
cmap_plasma.o: cmap_plasma.f95
	$(FC) $(INCLUDES) -c $(FCFLAGS) cmap_plasma.f95
cmap_viridis.o: cmap_viridis.f95
	$(FC) $(INCLUDES) -c $(FCFLAGS) cmap_viridis.f95
cmap_inferno.o: cmap_inferno.f95
	$(FC) $(INCLUDES) -c $(FCFLAGS) cmap_inferno.f95
cmap_blackbody.o: cmap_blackbody.f95
	$(FC) $(INCLUDES) -c $(FCFLAGS) cmap_blackbody.f95
cmap_kindlmann.o: cmap_kindlmann.f95
	$(FC) $(INCLUDES) -c $(FCFLAGS) cmap_kindlmann.f95
cmap_extendedkindlmann.o: cmap_extendedkindlmann.f95
	$(FC) $(INCLUDES) -c $(FCFLAGS) cmap_extendedkindlmann.f95
cmap_smoothcoolwarm.o: cmap_smoothcoolwarm.f95
	$(FC) $(INCLUDES) -c $(FCFLAGS) cmap_smoothcoolwarm.f95
cmap_bentcoolwarm.o: cmap_bentcoolwarm.f95
	$(FC) $(INCLUDES) -c $(FCFLAGS) cmap_bentcoolwarm.f95

# Extra targets.
clean:
	@rm -f $(EXECS) $(OBJS)

.PHONY: default clean
#End of the makefile
