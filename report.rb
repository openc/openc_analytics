# Inspired by https://gist.github.com/3166610
require 'google/api_client'
require 'google/api_client/client_secrets'
require 'google/api_client/auth/installed_app'
require 'google/api_client/auth/file_storage'
require 'date'
require 'statsd'

API_VERSION = 'v3'
CACHED_API_FILE = "analytics-#{API_VERSION}.cache"
CREDENTIAL_STORE_FILE = "#{$0}-oauth2.json"

class StatsThing
  def initialize
    client_secrets = Google::APIClient::ClientSecrets.load
    file_storage = Google::APIClient::FileStorage.new(CREDENTIAL_STORE_FILE)
    @authorization = client_secrets.to_authorization
    @statsd = Statsd.new('sys1', 8125)
    @namespace = 'openc.production'
    @profileID = "39301022"
    @client = Google::APIClient.new(
      :application_name => 'Ruby Service Accounts sample',
      :application_version => '1.0.0')
    flow = Google::APIClient::InstalledAppFlow.new(
      :client_id => client_secrets.client_id,
      :client_secret => client_secrets.client_secret,
      :scope => ['https://www.googleapis.com/auth/analytics.readonly']
    )

    # You can then use this with an API client, e.g.:
    if file_storage.authorization.nil?
      @client.authorization = flow.authorize(file_storage)
    else
      @client.authorization = file_storage.authorization
    end

    @analytics = nil
    # Load cached discovered API, if it exists. This prevents retrieving the
    # discovery document on every run, saving a round-trip to the discovery service.
    if File.exists? CACHED_API_FILE
      File.open(CACHED_API_FILE, "r") do |file|
        @analytics = Marshal.load(file)
      end
    else
      @analytics = @client.discovered_api('analytics', API_VERSION)
      File.open(CACHED_API_FILE, 'w') do |file|
        Marshal.dump(@analytics, file)
      end
    end
  end

  def tableoutput(data)
    puts "Data:"
    puts data.data.column_headers.map { |c|
      c.name
    }.join("\t")
    data.data.rows.each do |r|
      print r.join("\t"), "\n"
    end
  end

  def statsdoutput(data)
    key = data.data.column_headers.map { |c|
      c.name.sub("ga:", "")
    }.join(".")
    data.data.rows.each do |r|
      @statsd.gauge("#{@namespace}.#{key}", r[0].to_i)
    end
  end

  def visits
    startDate = DateTime.now.prev_month.strftime("%Y-%m-%d")
    endDate = DateTime.now.strftime("%Y-%m-%d")

    visitCount = @client.execute(:api_method => @analytics.data.ga.get, :parameters => {
      'ids' => "ga:" + @profileID,
      'start-date' => startDate,
      'end-date' => endDate,
      'dimensions' => "ga:day,ga:month",
      'metrics' => "ga:visits",
      'sort' => "ga:month,ga:day"
    })
    tableoutput(visitCount)
  end

  def social_interactions
    startDate = DateTime.now.prev_day.strftime("%Y-%m-%d")
    endDate = DateTime.now.strftime("%Y-%m-%d")

    interactions = @client.execute(:api_method => @analytics.data.ga.get, :parameters => {
      'ids' => "ga:" + @profileID,
      'start-date' => startDate,
      'end-date' => endDate,
      'metrics' => "ga:socialActivities"
    })
    statsdoutput(interactions)
  end

  def activeusers
    active = @client.execute(
      :api_method => @analytics.data.realtime.get, :parameters => {
        'ids' => "ga:" + @profileID,
        'metrics' => "rt:activeusers"
      })
    statsdoutput(active)
  end
end
thing = StatsThing.new
thing.activeusers
thing.social_interactions
#thing.visits
