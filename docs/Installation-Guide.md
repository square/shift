This guide is designed to get you up and running on your local development machine as quickly as possible.

### Dependencies
* **Ruby**: Use version 2.2 or later. Installation guides found [here](https://www.ruby-lang.org/en/documentation/installation/)
* **Go**: Use version 1.4 or later. Installation guides found [here](https://golang.org/doc/install)
* **MySQL**: Use version 5.5 or later. Installation guides found [here](https://dev.mysql.com/downloads/installer/)
* **Percona Toolkit**: Use version 2.2.15. Installation guides found [here](https://www.percona.com/downloads/percona-toolkit/2.2.15/)

### Apply the pt-online-schema-change patch
```
git clone https://github.com/square/shift.git
patch your/path/to/pt-online-schema-change shift/ptosc-patch/0001-ptosc-square-changes.patch
```

### Startup the rails server
```
# install rvm and ruby 2.2. see https://rvm.io/rvm/install
\curl -sSL https://get.rvm.io | bash
. .bash_profile
rvm install ruby-2.2
rvm use ruby-2.2

# clone the repo and install gems
git clone https://github.com/square/shift.git
cd shift/ui
gem install bundler
bundle install
# if bundle install complains about installing mysql2, try the following:
# yum install mysql-devel -y OR apt-get install libmysqlclient-dev

# Edit config/database.yml to include your database's connection details

# create the database and seed it with some data
bundle exec rake db:setup

# start the rails server
bundle exec rails server

# navigate to 127.0.0.1:3000 in your browser
```

### Startup the go runner
```
# get it and install dependencies
go get -v github.com/square/shift/...

cd $GOPATH/src/github.com/square/shift/runner
# Edit config/* as necessary

# start the runner
go run main.go -logtostderr
```