#!/usr/bin/env bash
set -euo pipefail
cat >REVIEW.md <<'EOF_FIXTURE'
# Review rules

- Never use `console.log` in src/. Use the logger in src/log.js.
EOF_FIXTURE
mkdir -p src
cat >src/greet.js <<'EOF_FIXTURE'
function greet(name) {
  const msg = 'hello ' + name
  console.log('greeting', name)
  return msg
}
module.exports = { greet }
EOF_FIXTURE
mkdir -p src
cat >src/log.js <<'EOF_FIXTURE'
module.exports = { info: function (m) { process.stderr.write(m + '\n') } }
EOF_FIXTURE
cat >change.diff <<'EOF_FIXTURE'
--- a/src/greet.js
+++ b/src/greet.js
@@ -1,4 +1,6 @@
 function greet(name) {
-  return 'hello ' + name
+  const msg = 'hello ' + name
+  console.log('greeting', name)
+  return msg
 }
 module.exports = { greet }
EOF_FIXTURE
