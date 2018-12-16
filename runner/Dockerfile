FROM golang:1.6

WORKDIR /go/src/github.com/square/shift/runner
COPY . .

RUN apt-get update && apt-get install -y perl build-essential libdbi-perl libdbd-mysql-perl libterm-readkey-perl libio-socket-ssl-perl libyaml-perl patch cpanminus
RUN cpanm YAML::Syck
RUN curl -sL -o pt-toolkit-2.2.15.deb https://www.percona.com/downloads/percona-toolkit/2.2.15/deb/percona-toolkit_2.2.15-2_all.deb && dpkg -i pt-toolkit-2.2.15.deb && rm pt-toolkit-2.2.15.deb && patch /usr/bin/pt-online-schema-change 0001-ptosc-square-changes.patch 

RUN go get github.com/tools/godep
RUN godep get ./...

ENV ENVIRONMENT env-based

CMD ["go", "run", "main.go", "-logtostderr"]8