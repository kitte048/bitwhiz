# Set up the path to include Fortran modules
INCLUDE_PATH = ../modules
INCLUDES = -I$(INCLUDE_PATH)

# The compiler
FC = gfortran

# The flags
FCFLAGS = -O3

# Start of the makefile (make object files only and do not link them)
SRCS = draw_colormaps.f95 draw_singlemap.f95 draw_blobs.f95
OBJS = $(SRCS:.f95=.o)
EXECS = server

server: $(OBJS) $(MOD_OBJS)

# Rules
draw_colormaps.o: draw_colormaps.f95
	$(FC) $(INCLUDES) -c $(FCFLAGS) draw_colormaps.f95
draw_singlemap.o: draw_singlemap.f95
	$(FC) $(INCLUDES) -c $(FCFLAGS) draw_singlemap.f95
draw_blobs.o: draw_blobs.f95
	$(FC) $(INCLUDES) -c $(FCFLAGS) draw_blobs.f95

# Extra targets.
clean:
	@rm -f $(EXECS) $(OBJS)

.PHONY: default clean
#End of the makefile
