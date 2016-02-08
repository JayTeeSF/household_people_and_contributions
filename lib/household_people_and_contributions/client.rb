module HouseholdPeopleAndContributions
  class Client
    def self.help(error_message = "")
      help_message = <<-HM
      #{error_message}

    KEY_FILE=`pwd`/config/f1_keys.rb ./bin/household_people_and_contributions.rb
    # OR:
    KEY_FILE=`pwd`/config/f1_keys.rb irb -r "./bin/household_people_and_contributions.rb"
    > hpac = HouseholdPeopleAndContributions::Client.new
    > hpac.pp
    > hpac.contributions_by_household
    > hpac.hh
      HM
      return help_message
    end

    def self.report
      new.report
    end

    CACHE_DIR = "./cache"
    fail help("missing cache_dir: #{CACHE_DIR.inspect}") unless File.exists?(CACHE_DIR)
    CONFIG_DIR = "./config"
    fail help("missing config_dir: #{CONFIG_DIR.inspect}") unless File.exists?(CONFIG_DIR)
    KEY_FILE = ENV['KEY_FILE']
    fail help("missing KEY_FILE: #{KEY_FILE.inspect}") unless KEY_FILE && File.exists?(KEY_FILE)
    require_relative(KEY_FILE)

    OUTPUT_DIR = "./output"
    fail help("missing output_dir: #{OUTPUT_DIR.inspect}") unless File.exists?(OUTPUT_DIR)

    MARSHALED_ACCESS_TOKEN_FILE = "#{CONFIG_DIR}/access_token_marshal.txt"
    YAMLED_ACCESS_TOKEN_FILE = "#{CONFIG_DIR}/access_token.yml"

    JSONED_CONTRIBUTION_FILE = "contribution_records.json"
    JSONED_PEOPLE_FILE = "people_records.json"
    JSONED_GRADE_FILE = "grade_records.json"
    JSONED_HOUSEHOLDS_FILE = "household_records.json"

    HOUSEHOLD_SEARCH_PATH_PREFIX = "/v1/Households/Search.json?include=communications&searchfor="
    PEOPLE_RECORDS_PATH_TEMPLATE = "/v1/Households/%s/People.json"
    ATTRIBUTED_SCHOLAR_RECORDS_PATH_FORMAT = "/v1/People/Search.json?id=%s&include=communications,attributes"
    CONTRIBUTION_RECORDS_PATH_TEMPLATE = "/giving/v1/contributionreceipts/search.json?householdID=%s&startReceivedDate=%s&endReceivedDate=%s"

    def key
      unless @key
        @key =
          F1Keys::CONSUMER_KEY
      end
      @key
    end

    def secret
      unless @secret
        @secret =
          F1Keys::CONSUMER_SECRET
      end
      @secret
    end

    def consumer
      unless @consumer
        @consumer = OAuth::Consumer.new(key, secret, {
          site: "https://#{F1Keys::CHURCH_CODE}.#{F1Keys::ENVIRONMENT}.fellowshiponeapi.com",
          request_token_path: "/v1/Tokens/RequestToken",
          authorize_path: "/v1/PortalUser/Login",
          # access_token_path: "/v1/Tokens/AccessToken",
          access_token_path: "/v1/PortalUser/AccessToken", # per some blog post

          http_method: :get, #vs. :post,
          scheme: :header, # vs. :body, # vs. :query_string,
        })
      end
      @consumer
    end

    def oauth_tokens?
      F1Keys::OAUTH_TOKEN && F1Keys::OAUTH_SECRET
    end

    def access_token
      unless @access_token
        if oauth_tokens?
          @access_token = OAuth::AccessToken.new(consumer, F1Keys::OAUTH_TOKEN, F1Keys::OAUTH_SECRET)
        end
        unless @access_token
          if File.exists?(MARSHALED_ACCESS_TOKEN_FILE)
            @access_token = Marshal::load(File.read(MARSHALED_ACCESS_TOKEN_FILE))
            # @access_token = YAML::load(File.read(YAMLED_ACCESS_TOKEN_FILE))
          end
        end
        unless @access_token
          # @request_token = @consumer.get_request_token('Authorization' => F1Keys::BODY)
          # @request_token = @consumer.get_request_token({}, F1Keys::BODY)
          # @request_token = @consumer.get_request_token({}, 'Authorize' => F1Keys::BODY)
          # @request_token = @consumer.get_request_token({request_body: F1Keys::BODY})
          @request_token = consumer.get_request_token()

          warn @request_token.token
          warn @request_token.secret

          warn "\nPaste URL into your browser:\n\n"

          warn @request_token.authorize_url

          warn "\nPress Enter when Done\n\n"

          gets

          @access_token = @request_token.get_access_token

          warn "Access Token:"
          warn @access_token.inspect
          warn "\nDone inspecting...\n"

          File.write(MARSHALED_ACCESS_TOKEN_FILE, Marshal.dump(@access_token))
          File.write(YAMLED_ACCESS_TOKEN_FILE, YAML.dump(@access_token))

          warn "\nAccess Token is now saved for future use"
        end
      end
      @access_token
    end

    def get(path, key=nil)
      loop_again = true
      current_page_number = 1
      records = []
      while loop_again
        paged_path = key.nil? ? path : "#{path}&page=#{current_page_number}"

        #warn "GET'ing: #{paged_path.inspect}..."
        response =  access_token.get(paged_path)

        response_body = response.body
        #warn "BODY: #{response_body.inspect}..."
        json_body = JSON.parse(response_body)

        results = key.nil? ? json_body : json_body[key]

        records << results

        if results["@additionalPages"] && results["@additionalPages"] != "0"
          loop_again = true
          fail("odd page number: #{results['@pageNumber']}") unless results["@pageNumber"] == current_page_number.to_s
          current_page_number += 1
          sleep 5
        else
          loop_again = false
        end
      end
      return records
    end

    def lookup(records_path, cache_file, options={})
      if options.key?(:prefix) && options[:prefix]
        cache_file = options[:prefix] + "_" + cache_file
      end
      cache_file =  CACHE_DIR + "/" + cache_file
      if File.exists?(cache_file)
        results_array = JSON.parse(File.read(cache_file))
      else
        results_array = get(records_path, options[:key])
        File.write(cache_file, results_array.to_json)
      end
      return results_array
    end

    def household_records(household_records_path)
      @household_records = []
      household_results = lookup(household_records_path, JSONED_HOUSEHOLDS_FILE, key: "results")

      household_results.each do |results|
        household_array = results["household"]
        @household_records += household_array.reduce([]) { |memo, household_record|
          tmp_record = {}
          tmp_record["key"] = household_record["@id"]
          tmp_record["name"] = household_record["householdName"]
          tmp_record["sort_name"] = household_record["householdSortName"]
          tmp_record["created_at"] = household_record["createdDate"]
          tmp_record["updated_at"] = household_record["lastUpdatedDate"]
          memo << tmp_record.dup
          memo
        }
      end
      @household_records
    end

    def get_contributions_for_households(households=[], from=nil, upto_but_not_including=nil)
      @contributions = []
      household_ids_for(households).each do |household_id|
        @contributions += contribution_records(household_id, from, upto_but_not_including)
      end
      return @contributions
    end

    # may-1 -> may-1
    # if < may1 # jan - apr 30th ...current-year
    # if >= may1 # may - dec ...next-year
    def contribution_records(household_id, from=nil, upto_but_not_including=nil)
      @contribution_records = []
      unless from
        current_time = Time.now.utc
        current_month = current_time.month

        current_year = current_time.year
        previous_year = current_year - 1
        next_year = current_year + 1

        if current_month < 5 # we're nearing the end of the cycle
          # from previous year, to current-year
          from = "#{previous_year}-05-01" # TBD: make this configurable!
          upto_but_not_including ||= "#{current_year}-05-01"
        else
          # from current year, to next-year
          from = "#{current_year}-05-01"
          upto_but_not_including ||= "#{next_year}-05-01"
        end
      end

      path_params = [household_id, from, upto_but_not_including]
      contributions_path = CONTRIBUTION_RECORDS_PATH_TEMPLATE % path_params
      contributions_path = "#{contributions_path}&recordsPerPage=200"

      contribution_results = lookup(contributions_path, JSONED_CONTRIBUTION_FILE, key: "results", prefix: path_params.join('_'))

      contribution_results.each do |results|
        if contribution_array = results["contributionReceipt"]
          @contribution_records += contribution_array.reduce([]) { |memo, contribution_record|
            tmp_record = {}
            tmp_record["key"] = contribution_record["@id"]
            tmp_record["amount"] = contribution_record["amount"]
            tmp_record["fund_key"] = contribution_record["fund"]["@id"]
            tmp_record["fund_name"] = contribution_record["fund"]["name"]
            tmp_record["household_key"] = contribution_record["household"]["@id"]
            tmp_record["received_date"] = contribution_record["receivedDate"]
            tmp_record["transmit_date"] = contribution_record["transmitDate"]
            tmp_record["created_at"] = contribution_record["createdDate"]

            tmp_record["updated_at"] = contribution_record["lastUpdatedDate"]
            memo << tmp_record.dup
            memo
          }
        end
      end
      @contribution_records
    end

    SCHOLAR_STATUS = "scholar"
    PARENT_STATUS = "parent"
    VALID_STATUSES = [SCHOLAR_STATUS, PARENT_STATUS]
    def people_records(household_id)
      people_records_path = PEOPLE_RECORDS_PATH_TEMPLATE % household_id

      @people_records = []
      people_results = lookup(people_records_path, JSONED_PEOPLE_FILE, prefix: household_id)

      people_results.each do |results|
        persons_array = results["people"]["person"]
        @people_records += persons_array.reduce([]) { |memo, person_record|

          status = person_record["status"]["name"].downcase
          if VALID_STATUSES.include?(status) && household_id == person_record["@householdID"]
            tmp_record = {}

            tmp_record["key"] = person_record["@id"]
            tmp_record["household_key"] = person_record["@householdID"]
            tmp_record["status"] = status

            tmp_record["first_name"] = person_record["firstName"]
            tmp_record["last_name"] = person_record["lastName"]
            tmp_record["suffix"] = person_record["suffix"]

            tmp_record["created_at"] = person_record["createdDate"]
            tmp_record["updated_at"] = person_record["lastUpdatedDate"]

            memo << tmp_record.dup
          end
          memo
        }
      end
      @people_records
    end

    def household_ids_for(households)
      households.map { |household_record| household_record["key"] }
    end

    def get_people_in_households(households=[])
      @people = []
      household_ids_for(households).each do |household_id|
        @people += people_records(household_id)
      end
      return @people
    end

    def parent_records(id_list_csv, options={})
      @parent_records = []
      emailable_parent_records_path = ATTRIBUTED_SCHOLAR_RECORDS_PATH_FORMAT % id_list_csv
      emailable_parent_records_path = "#{emailable_parent_records_path}&#{options[:extra_params]}"
      parent_results = lookup(emailable_parent_records_path, JSONED_GRADE_FILE, prefix: id_list_csv.gsub(',','_'))

      parent_results.each do |results|
        parents_array = results["results"]["person"]
        @parent_records += parents_array.reduce([]) { |memo, parent_record|

          if parent_record["communications"]
            tmp_record = {}
            communications_array = parent_record["communications"]["communication"]
            communications_array.each do |communication_entry|
              if communication_entry["communicationType"]["name"].downcase == "email"
                tmp_record["key"] = communication_entry["person"]["@id"]
                tmp_record["email"] = communication_entry["communicationValue"]
              end
            end
            memo << tmp_record.dup if tmp_record["email"]
          end
          memo
        }
      end
      @parent_records
    end

    def scholar_records(id_list_csv, options={})
      @scholar_records = []
      attributed_scholar_records_path = ATTRIBUTED_SCHOLAR_RECORDS_PATH_FORMAT % id_list_csv
      attributed_scholar_records_path = "#{attributed_scholar_records_path}&#{options[:extra_params]}"
      scholar_results = lookup(attributed_scholar_records_path, JSONED_GRADE_FILE, prefix: id_list_csv.gsub(',','_'))

      scholar_results.each do |results|
        scholars_array = results["results"]["person"]
        @scholar_records += scholars_array.reduce([]) { |memo, scholar_record|

          tmp_record = {}
          attributes_array = scholar_record["attributes"]["attribute"]
          attributes_array.each do |attribute_entry|
            if attribute_entry["attributeGroup"]["name"].downcase == "grade"
              tmp_record["key"] = attribute_entry["person"]["@id"]
              tmp_record["grade"] = attribute_entry["attributeGroup"]["attribute"]["name"]
            end
          end
          memo << tmp_record.dup if tmp_record["grade"]
          memo
        }
      end
      @scholar_records
    end


    def get_people_email_for(people=[], options = {})
      n_at_a_time = options[:recordsPerPage] || 200
      @emailable_people = []
      #warn "\n\n\t------------------> HERE\n\n"
      parents = people.select { |person| PARENT_STATUS == person["status"].downcase }
      #warn "\n\tparents: #{parents.inspect}\n\n\n"
      extra_params = "recordsPerPage=#{n_at_a_time}"
      while !parents.empty?
        parent_id_list = parents.pop(n_at_a_time).map {|s| s["key"] }
        parent_id_list_csv = parent_id_list.join(",")
        @emailable_people += parent_records(parent_id_list_csv, extra_params: extra_params)
      end

      return @emailable_people
    end

    def get_scholar_grades_for(people=[], options = {})
      n_at_a_time = options[:recordsPerPage] || 200
      @attributed_scholars = []
      #warn "\n\n\t------------------> HERE\n\n"
      scholars = people.select { |person| SCHOLAR_STATUS == person["status"].downcase }
      #warn "\n\tscholars: #{scholars.inspect}\n\n\n"
      extra_params = "recordsPerPage=#{n_at_a_time}"
      while !scholars.empty?
        scholar_id_list = scholars.pop(n_at_a_time).map {|s| s["key"] }
        scholar_id_list_csv = scholar_id_list.join(",")
        @attributed_scholars += scholar_records(scholar_id_list_csv, extra_params: extra_params)
      end

      return @attributed_scholars
    end

    def add_contribution_sum_to_households(contributions, hh)
      contributions.each do |contribution_record|
        household = hh.detect { |h| h["key"] == contribution_record["household_key"] }
        if household
          household["contribution_total"] ||= 0
          household["contribution_total"] += contribution_record["amount"].to_f
        end
      end
      return hh
    end

    def add_email_to_people(em, pp)
      em.each do |parent|
        person = pp.detect { |p| p["key"] == parent["key"] }
        if person
          person["email"] = parent["email"]
        end
      end
      return pp
    end

    def add_grades_to_people(as, pp)
      as.each do |scholar|
        person = pp.detect { |p| p["key"] == scholar["key"] }
        if person
          person["grade"] = scholar["grade"]
        end
      end
      return pp
    end

    # get all the household(s):
    def hh
      unless @hh
        query = "%"
        path = "#{HOUSEHOLD_SEARCH_PATH_PREFIX}#{query}"
        household_records_path = "#{path}&recordsPerPage=200"
        #warn "-> Search Households for #{query}..."
        @hh = household_records(household_records_path)
      end
      @hh
    end

    # get the people in each household:
    def pp
      unless @pp
        @pp = get_people_in_households(hh)
      end
      @pp
    end

    # attribute the people that are scholars w/ a grade(-level)
    def as
      unless @as
        @as = get_scholar_grades_for(pp, recordsPerPage: 200)
        @em = get_people_email_for(pp, recordsPerPage: 200)
        @pp = add_email_to_people(@em, pp)
        @pp = add_grades_to_people(@as, pp)
      end
      @as
    end

    #Search for receipts containing the householdID that is passed with this parameter.
    #startReceivedDate = search for receipts with a received date greater than or equal to this parameter (format: yyyy-mm-dd).
    #endReceivedDate = search for receipts with a received date less than or equal to this parameter. Must be used in conjunction with startReceivedDate (format: yyyy-mm-dd).
    #ex. startReceivedDate=2014-12-15&endReceivedDate=2014-12-16 will give you a 24 hour period.
    def contributions_by_household
      unless @contributions_by_household
        @contributions_by_household = get_contributions_for_households(hh)
        # merge with household data
        @hh = add_contribution_sum_to_households(@contributions_by_household, hh)
      end
      @contributions_by_household
    end

    def report
      as # get people, add grades to them...
      #warn "\n--> people and scholars: "
      File.write(OUTPUT_DIR + "/" + "people.json", pp.to_json)
      puts pp.to_json

      #warn "\n--> contributions: "
      File.write(OUTPUT_DIR + "/" + "contributions.json", contributions_by_household.to_json)
      puts contributions_by_household.to_json

      #warn "--> hh: "
      File.write(OUTPUT_DIR + "/" + "households.json", hh.to_json)
      puts hh.to_json

      return {hh: @hh, pp: @pp, contributions_by_household: @contributions_by_household}
    end
  end
end
