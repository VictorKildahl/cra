# A scenario file's line as scripts/scenario.sh reads it. `scenario_line "<raw line>"` prints the line without its
# comment and trailing space (scenario.sh then fills in ${PAGE} and the rest), and returns 1 for a comment line.
# A line starting with # is a comment, and so is the rest of a line after a space, # and a space
# ("budget stalls50=6   # why"). A # with text right after it belongs to the line: `expect-log fill #4B2323`, a
# cra:// URL's fragment. Every line used to be cut at its first #, so such a check tested only "fill ".
scenario_line() {
  local raw="$1" line
  [[ "$raw" =~ ^[[:space:]]*# ]] && return 1
  line="${raw%%[[:space:]]#[[:space:]]*}"
  line="${line%[[:space:]]#}"
  printf '%s\n' "${line%"${line##*[![:space:]]}"}"
}
