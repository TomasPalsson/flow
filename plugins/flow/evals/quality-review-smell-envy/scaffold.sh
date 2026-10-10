#!/usr/bin/env bash
set -euo pipefail
mkdir -p src
cat >src/invoice.js <<'EOF_FIXTURE'
class Order {
  constructor(items, tax, discount) {
    this.items = items
    this.tax = tax
    this.discount = discount
  }
}

class InvoicePrinter {
  total(order) {
    const sum = order.items.reduce(function (a, i) { return a + i.price * i.qty }, 0)
    return sum * (1 + order.tax) - order.discount
  }
}
module.exports = { Order, InvoicePrinter }
EOF_FIXTURE
cat >change.diff <<'EOF_FIXTURE'
--- a/src/invoice.js
+++ b/src/invoice.js
@@ -6,3 +6,10 @@
   }
 }

+class InvoicePrinter {
+  total(order) {
+    const sum = order.items.reduce(function (a, i) { return a + i.price * i.qty }, 0)
+    return sum * (1 + order.tax) - order.discount
+  }
+}
+module.exports = { Order, InvoicePrinter }
EOF_FIXTURE
