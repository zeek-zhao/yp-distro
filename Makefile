.PHONY: help config doctor image source build qemu review test report e2e lint secret-scan ci-tools

help:
	@printf '%s\n' 'Targets: config doctor image source build qemu review test report e2e lint secret-scan ci-tools'

config doctor image source build qemu review test report e2e:
	./project.sh $@

lint:
	bash scripts/ci/lint.sh

secret-scan:
	bash scripts/ci/secret-scan.sh

ci-tools:
	bash scripts/ci/install-tools.sh
