# orgmem on a container host (Railway/Render/Fly).
#
# Three things make this non-obvious, all of them recorded here rather than
# rediscovered:
#
#  1. Jac 0.34.3 is NOT on PyPI — PyPI's newest is 0.16.7, which cannot run
#     this code. The language is installed from source at a pinned commit and
#     put on PYTHONPATH, shadowing the pip package. The pip package is still
#     installed, purely for its `jac` console script and dist metadata. This
#     mirrors activate.sh exactly.
#  2. Jac 0.34.x needs Python >= 3.14. On 3.12/3.13 it dies at import with
#     `cannot import name 'EllipsisType' from 'types'`.
#  3. The Jac runtime does not search PATH for bun. It needs an absolute path
#     in JAC_BUN or every client build fails with "bun is not available in
#     this jac runtime".
FROM python:3.14-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl unzip ca-certificates build-essential \
    && rm -rf /var/lib/apt/lists/*

# bun, for the client bundle.
RUN curl -fsSL https://bun.sh/install | bash
ENV JAC_BUN=/root/.bun/bin/bun

# The language itself, pinned to the commit the wiki was distilled from.
RUN git clone https://github.com/jaseci-labs/jac /opt/jac \
    && cd /opt/jac && git checkout 5f4f7b6d || true
ENV PYTHONPATH=/opt/jac/jac

# Console script + metadata only; PYTHONPATH above wins for the actual import.
RUN pip install --no-cache-dir jaclang==0.16.7 pandas pyarrow

WORKDIR /app
COPY . /app

# The graph is built at import (~6s, 76,787 edges) and held in memory, so this
# must be a long-lived process — it is not a serverless workload.
ENV PORT=8080
CMD ["sh", "-c", "jac dev app.jac -p ${PORT}"]
