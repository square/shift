FROM ruby:2.2
RUN apt-get update -qq && apt-get install -y build-essential ruby-dev libgmp3-dev
RUN mkdir /shift-ui
WORKDIR /shift-ui
COPY Gemfile /shift-ui/Gemfile
COPY Gemfile.lock /shift-ui/Gemfile.lock

# RUN gem install bundler
RUN bundle install

COPY . /shift-ui

EXPOSE 3000
