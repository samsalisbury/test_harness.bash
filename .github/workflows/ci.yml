name: CI
on: push
jobs:
  test:
    runs-on: ubuntu-18.04
    steps:
      - uses: actions/checkout@master
      - uses: docker://bash:${{ matrix.bash-version }}
        run: make test
        shell: /usr/bash -euo pipefail {0}
strategy:
  matrix:
    bash-version: [5.0.7, 3.2.57]
