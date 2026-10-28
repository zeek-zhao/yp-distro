PROJECT_TARGETS = config doctor image source build qemu review test report e2e lint secret-scan ci-tools hooks shell

.PHONY: help $(PROJECT_TARGETS)

help:
	@printf '%s\n' 'Targets: $(PROJECT_TARGETS)'

config:
	./project.sh config

doctor:
	./project.sh doctor

image:
	./project.sh image

source:
	./project.sh source

build:
	./project.sh build

qemu:
	./project.sh qemu

review:
	./project.sh review

test:
	./project.sh test

report:
	./project.sh report

e2e:
	./project.sh e2e

lint:
	./project.sh lint

secret-scan:
	./project.sh secret-scan

ci-tools:
	./project.sh ci-tools

hooks:
	./project.sh hooks

shell:
	./project.sh shell
