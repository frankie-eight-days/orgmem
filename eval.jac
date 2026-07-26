"""Run the ground-truth benchmark and write `eval_results.json`.

Separate from `main.jac` because `jac dev` does not expose `/walker/*` routes,
so the score cannot be reproduced against the running app. Run it with the dev
server stopped — both processes open the same persisted graph under `.jac/`.

    jac run eval.jac
"""

import from main { EvalRun }


with entry {
    root spawn EvalRun();
}
