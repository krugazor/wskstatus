FROM swift:5.3

RUN apt-get update
RUN apt-get install openssl libssl-dev libcurl4-openssl-dev
RUN apt-get install dumb-init

RUN mkdir /wskstatus
COPY Package.swift /wskstatus/Package.swift
COPY Sources /wskstatus/Sources
COPY Tests /wskstatus/Tests

WORKDIR /wskstatus

RUN swift build -c release

EXPOSE 8085

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD swift run -c release wskstatus
