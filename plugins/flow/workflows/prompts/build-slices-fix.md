Fix the adversarial findings given in the prompt, against the brief and diff paths given there.

First classify each finding as contract-misread (the task contract, not the code, is wrong) or code-defect. For a misread, do not code around it: return it in misreads with a ruling and an --amend proposal. If you dispute a finding, return it in rejected with finding (its predicate, verbatim) and a receipt: a path:line, a command, or a no-callers grep. A rejection without a receipt counts as not addressed.

Run the test command given in the prompt. Return the updated TASK_RESULT.
