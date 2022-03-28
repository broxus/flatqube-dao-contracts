compile:
	@echo Compiling:
	npx locklift build --config locklift.config.js


file=test/*
network=local
tests:
	@echo Running test $(file) on network $(network):
	npx locklift test --config locklift.config.js --network $(network) --tests $(file)
