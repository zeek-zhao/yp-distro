.PHONY: help config doctor image source build qemu review test report e2e lint secret-scan ci-tools hooks

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

# 安装仓库级 git 钩子（阻止直推 main），一次性动作
hooks:
	git config core.hooksPath .githooks
	chmod +x .githooks/*
	@printf 'core.hooksPath = %s\n' "$$(git config core.hooksPath)"
