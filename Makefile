.PHONY: build test snapshot coverage
build:
	forge build --sizes
test:
	forge test -vv
snapshot:
	forge snapshot
coverage:
	forge coverage --report lcov

