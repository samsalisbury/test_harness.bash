ARG BASH_VERSION
FROM bash:$BASH_VERSION

RUN apk add make bc coreutils

COPY . ./

CMD make test-alls-shouldfail
