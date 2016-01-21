# edit the sample from this gem (/repo), to setup your f1_keys.rb file
# e.g.
# gem which household_people_and_contributions
# now get the sample config file that is relative to the parent directory of that file's directory
# config/f1_keys_rb.sample
# be sure you have the local dirs:
#  o  cache
#  o  config
#  o  output

KEY_FILE=`pwd`/config/f1_keys.rb ./bin/household_people_and_contributions.rb
# OR:
KEY_FILE=`pwd`/config/f1_keys.rb irb -r "./bin/household_people_and_contributions.rb"
> hpac = HouseholdPeopleAndContributions.new
> hpac.pp
> hpac.contributions_by_household
> hpac.hh
