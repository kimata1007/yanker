# Shared test scaffolding. Every test_*.zsh is sourced with this already loaded.

typeset -g YANKER_TEST_RUN=0
typeset -g YANKER_TEST_FAILED=0

# Repository root
typeset -g YANKER_ROOT=${0:A:h:h}

assert_equal() {
  local desc=$1 expected=$2 actual=$3
  YANKER_TEST_RUN=$(( YANKER_TEST_RUN + 1 ))
  if [[ "$expected" == "$actual" ]]; then
    print -r -- "  ok   $desc"
    return 0
  fi
  YANKER_TEST_FAILED=$(( YANKER_TEST_FAILED + 1 ))
  print -r -- "  FAIL $desc"
  print -r -- "         expected: [$expected]"
  print -r -- "         actual:   [$actual]"
  return 1
}

assert_status() {
  local desc=$1 expected=$2 actual=$3
  assert_equal "$desc" "$expected" "$actual"
}
