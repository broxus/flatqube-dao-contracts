compile:
	@echo Compiling:
	npx locklift build


file=
network=local
tests:
	@echo Running test $(file) on network $(network):
	npx locklift test --network $(network) --tests $(file)
