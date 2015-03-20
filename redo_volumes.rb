require 'awesome_print'
require 'aws-sdk'
require 'pry'

desired_instance_name = ARGV[0]
if desired_instance_name.nil?
  puts "Input the name of the instance you want yo."
  exit
end

credentials = Aws::Credentials.new(
  ENV['AWS_ACCESS_KEY'],
  ENV['AWS_SECRET_KEY']
)

client = Aws::EC2::Client.new(
  region: 'us-west-2',
  credentials: credentials
)

instance = client.describe_instances(
  filters:[ {
    name: 'tag-value',
    values: [ desired_instance_name ]
  }]
)

if instance.first.reservations.empty?
  puts "Can't find #{desired_instance_name}"
  exit
end

instance_id = instance.reservations[0].instances[0].instance_id
puts "Instance ID: #{instance_id}"

volumes = instance.reservations[0].instances[0].block_device_mappings.to_a

ebs_volumes = []
volumes.each do |volume|
  unless volume[0] == "/dev/sda1"
    ebs_volumes << volume[1].volume_id
  end
end

puts "Found #{ebs_volumes.count} ebs volume(s):"
puts ebs_volumes

ebs_volumes.each do |volume|
  puts "#{volume} status: #{client.describe_volumes(volume_ids: [volume]).values}"
end
