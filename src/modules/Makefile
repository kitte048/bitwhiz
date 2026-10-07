# The compiler
FC = gfortran

# The flags
FCFLAGS = -std=f2018 -Wall -Wextra -Wno-implicit-interface -Wsurprising \
	-Waliasing -Wampersand -Wconversion -Wcharacter-truncation \
	-Wline-truncation -fcheck=all -fbacktrace -g -O0 \
	-ffpe-trap=invalid,zero,overflow -finit-real=snan \
	-finit-integer=-999999 -fconvert=little-endian -fimplicit-none

# Start of the makefile.
SRCS = shock_mod.f95 bit_mod.f95 plas_mod.f95 viri_mod.f95 \
	kndl_mod.f95 infr_mod.f95 bbdy_mod.f95 \
	ekdl_mod.f95 smcw_mod.f95 btcw_mod.f95 \
	rand_mod.f95
OBJS = $(SRCS:.f95=.o)
MOD_OBJS = shock.mod bits.mod plasma.mod viridis.mod \
	kindlmann.mod inferno.mod blackbody.mod \
	extendedkindlmann.mod \
	smoothcoolwarm.mod bentcoolwarm.mod \
	random.mod

server: $(OBJS)

# Rules
shock_mod.o: shock_mod.f95
	$(FC) -c $(FCFLAGS) shock_mod.f95
bit_mod.o: bit_mod.f95
	$(FC) -c $(FCFLAGS) bit_mod.f95
plas_mod.o: plas_mod.f95
	$(FC) -c $(FCFLAGS) plas_mod.f95
viri_mod.o: viri_mod.f95
	$(FC) -c $(FCFLAGS) viri_mod.f95
kndl_mod.o: kndl_mod.f95
	$(FC) -c $(FCFLAGS) kndl_mod.f95
infr_mod.o: infr_mod.f95
	$(FC) -c $(FCFLAGS) infr_mod.f95
bbdy_mod.o: bbdy_mod.f95
	$(FC) -c $(FCFLAGS) bbdy_mod.f95
ekdl_mod.o: ekdl_mod.f95
	$(FC) -c $(FCFLAGS) ekdl_mod.f95
smcw_mod.o: smcw_mod.f95
	$(FC) -c $(FCFLAGS) smcw_mod.f95
btcw_mod.o: btcw_mod.f95
	$(FC) -c $(FCFLAGS) btcw_mod.f95
rand_mod.o: rand_mod.f95
	$(FC) -c $(FCFLAGS) rand_mod.f95

# Extra targets.
clean:
	@rm -f $(EXECS) $(OBJS) $(MOD_OBJS)

.PHONY: default clean
#End of the makefile
