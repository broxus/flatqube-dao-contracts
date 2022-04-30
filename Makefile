compile:
	@echo Compiling:
	npx locklift build


file=test/
network=local
tests:
	@echo Running test $(file) on network $(network):
	npx locklift test --network $(network) --test $(file) --enable-tracing --external-build node_modules/broxus-ton-tokens-contracts/build
