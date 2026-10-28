.PHONY: help config doctor image source build qemu review test report e2e

help:
	@printf '%s\n' 'Targets: config doctor image source build qemu review test report e2e'

config doctor image source build qemu review test report e2e:
	./project.sh $@
