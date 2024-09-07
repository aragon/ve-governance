#!/bin/sh

echo "Removing test, script and src/escrow/increasing/delegation files from coverage report"
forge coverage --report lcov &&
  lcov --remove ./lcov.info -o ./lcov.info.pruned \
    'test/**/*.sol' 'script/**/*.sol' 'test/*.sol' \
    'script/*.sol' 'src/escrow/increasing/delegation/*.sol' &&
  genhtml lcov.info.pruned -o report --branch-coverage
