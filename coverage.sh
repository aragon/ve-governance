#!/bin/sh

forge coverage --report lcov &&
  lcov --remove ./lcov.info -o ./lcov.info.pruned \
    'test/**/*.sol' 'script/**/*.sol' 'test/*.sol' \
    'script/*.sol' &&
  genhtml lcov.info.pruned -o report --branch-coverage
