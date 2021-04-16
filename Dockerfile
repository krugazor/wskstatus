FROM swift:5.3

RUN mkdir /wskstatus
COPY Package.swift /wskstatus/Package.swift
COPY Sources /wskstatus/Sources
COPY Tests /wskstatus/Tests

WORKDIR /wskstatus

RUN swift build -c release 

CMD swift run -c release wskstatus