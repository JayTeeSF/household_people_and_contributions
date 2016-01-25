#!/usr/bin/env ruby

begin
  require "rubygems"
  gem "household_people_and_contributions"
  require "household_people_and_contributions"
rescue LoadError => e
  warn "LoadError: #{e.message.inspect}"
  require_relative "../lib/household_people_and_contributions"
end

if File.basename(__FILE__) == File.basename($PROGRAM_NAME)
  HouseholdPeopleAndContributions::Client.report
end
