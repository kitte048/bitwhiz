# Use this Makefile for manual clean-up, or compile w/o executables.
TYPE = clean

# Default behavior is clean up.
default: clean

clean:
	rm -f *.mod *.o *.a */*.o */*.mod

############################################################
###  NOTES: this simple target works, because the modules
###  are compiled first.
############################################################

code:
	@if [ -d modules ]; then \
		echo "processing folder ==> modules"; \
		$(MAKE) -C modules; \
	fi; \
	for a in $$(ls); do \
		if [ -d $$a ]; then \
			echo "processing folder ==> $$a"; \
			$(MAKE) -C $$a; \
		fi; \
	done;
