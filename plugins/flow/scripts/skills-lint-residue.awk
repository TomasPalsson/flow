# skills-lint-residue.awk — used by skills-lint (kept out of that file to stay
# under the size guard's file-length limit).
#
# Prints "RESIDUE <file>:<line> <text>" for each of the last 3 non-blank lines
# outside code fences that reads like an assistant sign-off ("Excellent work!
# ... Would you like me to ...") left at the tail of a shipped prompt. Only the
# tail is judged: a scripted reply quoted mid-file is documentation, not residue.
# Usage: awk -f skills-lint-residue.awk <file.md>
BEGIN { infence = 0; n = 0 }
{
  t = $0
  sub(/^[ \t]*/, "", t)
  if (t ~ /^(```|~~~)/) { infence = !infence; next }
  if (infence || t == "") next
  n++
  line[n] = NR
  text[n] = $0
}
END {
  for (i = (n > 3 ? n - 2 : 1); i <= n; i++) {
    l = tolower(text[i])
    if (l ~ /would you like me to|excellent work|is now complete|let me know if|i hope this helps/)
      printf "RESIDUE %s:%d %s\n", FILENAME, line[i], substr(text[i], 1, 100)
  }
}
