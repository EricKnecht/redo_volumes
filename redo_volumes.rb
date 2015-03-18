require 'aws-sdk'
require 'pry'

credentials = Aws::Credentials.new(
  ENV['AWS_ACCESS_ID'],
  ENV['AWS_SECRET_ACCESS_KEY']
)

client = Aws::EC2::Client.new(
  region: 'us-west-2',
  credentials: credentials
)

instance = client.describe_instances(
  filters:[ {
    name: 'tag-value',
    values: ["#{ARGV[0]}"]
  }]
)

instance.each do |item|
  binding.pry
end
