#!/bin/sh

echo "Removing test, script and src/escrow/increasing/delegation and proxylib files from coverage report"
forge coverage --no-match-path "test/fork/**/*.sol" --report lcov &&
	lcov --remove ./lcov.info -o ./lcov.info.pruned \
		'test/**/*.sol' 'script/**/*.sol' 'test/*.sol' \
		'script/*.sol' 'src/escrow/increasing/delegation/*.sol' \
		'src/libs/ProxyLib.sol' &&
	genhtml lcov.info.pruned -o report --branch-coverage
