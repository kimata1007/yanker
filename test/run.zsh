#!/usr/bin/env zsh
# Test runner. Runs every test/test_*.zsh and exits 1 if any assertion failed.
#
# err_return is deliberately not set: a failing assertion would abort the rest
# of the run and hide how many tests actually broke. Count them and decide at
# the end instead.
emulate -L zsh

typeset -g TEST_DIR=${0:A:h}
source $TEST_DIR/helper.zsh

typeset -a files=($TEST_DIR/test_*.zsh(N))
if (( ! $#files )); then
  print -ru2 -- 'no test files found'
  exit 1
fi

typeset f
for f in $files; do
  print -r -- "${f:t:r}"
  source $f
done

print -r -- ''
print -r -- "${YANKER_TEST_RUN} tests, ${YANKER_TEST_FAILED} failed"
(( YANKER_TEST_FAILED == 0 ))
