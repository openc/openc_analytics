require "statsd"
require "open3"
require "json"

@statsd = Statsd.new("sys1", 8125)
@urls = JSON.parse(File.read("worst-offender-urls.json"))
@repetitions = 10

def get_average_response_time(url:, repetitions: 10)
  command = "siege --verbose --no-parser --concurrent 1 --benchmark --reps #{repetitions} #{url}"
  puts "Running siege on #{url}"
  $stdout.flush

  stdout, stderr, status = Open3.capture3(command)
  puts stdout
  puts stderr
  raise "Error running siege: #{stderr[0..800]}" unless status.success?

  response_time_string = stderr[/Response time:\s*(.*?)\ssecs\n/, 1]
  raise "regexp failed to find 'Response time' from output" if response_time_string.nil?
  response_time = Float(response_time_string)
  puts "parsed response_time: #{response_time}"

  response_time
end

def statsd_output(page_name, response_time)
  stat_name = "response_times.worst_offenders.#{page_name}"
  puts "Sending to StatsD #{stat_name} : #{response_time}"
  @statsd.gauge(stat_name, response_time)
end

$stdout.sync = true
puts "==== Worst offenders : #{Time.now.utc} ===="
reading_count = 0
total_response_time = 0
@urls.each do |page_name, url|
  puts "---- #{page_name} : #{Time.now.utc} ----"
  response_time = get_average_response_time(url: url, repetitions: @repetitions)
  statsd_output(page_name, response_time)

  reading_count += 1 if response_time > 0
  total_response_time += response_time
end
puts "We only got #{reading_count} response time readings" if reading_count < @urls.size
average_response_time = reading_count.zero? ? 0 : total_response_time / reading_count
statsd_output("average", average_response_time)
puts "DONE #{Time.now.utc}\n"
