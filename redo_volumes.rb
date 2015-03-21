require 'awesome_print'
require 'aws-sdk'
require 'pry'
ENV["AWS_REGION"] = 'us-west-2'



def stop_mongo instance
  #Lazy hack, shell out to ssh
  `ssh -t #{instance.private_ip_address} sudo /etc/init.d/mongod stop`
  sleep 5
  `ssh -t #{instance.private_ip_address} sudo umount /data`
  `ssh -t #{instance.private_ip_address} sudo mdadm --stop /dev/md0`
end


def start_mongo instance
  sleep 15
  #Lazy hack, shell out to ssh
  `ssh -t #{instance.private_ip_address} sudo mdadm --assemble --scan`
  `ssh -t #{instance.private_ip_address} sudo mount /data`
  `ssh -t #{instance.private_ip_address} sudo /etc/init.d/mongod start`
end

def snapshot_volumes instance
  snapshots = []
  instance.volumes.each do |volume|
    next if volume.tags.empty?
    snapshot = volume.create_snapshot
    snapshots << snapshot
    tag_value = volume.tags.select { |t| t.key == 'Name'}.first.value
    snapshot.create_tags( :tags => [ {:key => 'Name', :value => tag_value}])
  end
  #neat bit from v2
  snapshots.each do |snapshot|
    snapshot.wait_until_completed do |w|
      w.interval = 60
      w.max_attempts = 120
    end
  end
  snapshots
end


def create_gp2_from_snapshots snapshots, client, zone
  volumes = []
  snapshots.each do |snapshot|
    response = client.create_volume(
      snapshot_id: snapshot.id,
      availability_zone: zone,
      volume_type: "gp2",
      encrypted: true,
    )
    volume_id = response.volume_id
    volume    = Aws::EC2::Volume.new(volume_id, :region => 'us-west-2')
    #refresh snapshot
    snapshot  = Aws::EC2::Snapshot.new(snapshot.id)
    tag_value = snapshot.tags.select { |t| t.key == 'Name'}.first.value
    volume.create_tags( :tags => [ {:key => 'Name', :value => tag_value}])

    volumes << volume
    while Aws::EC2::Volume.new(volume_id).state != 'available'
      puts "Waiting for volume to become available"
      sleep 5 
    end
  end
  volumes
end


def detach_and_attach instance, new_volumes

  volumes = instance.volumes.select{ |v| !v.tags.empty? }
  instance.volumes.each do  | volume |
    next if volume.tags.empty?
    volume.detach_from_instance(
      :instance_id => instance.id,
      :force => true
    )
  end


  available_count = 0 
  while available_count != 4
    available_count = 0 
    puts "WAITING FOR VOLUMES TO DETACH"
    sleep 30
    volumes.each do |v|
      available = Aws::EC2::Volume.new(v.id).state == 'available'
      available_count += 1 if available
    end
  end
  new_volumes.each do |volume|

    device = volume.tags.select {|t|t.key == 'Name'}.first.value.split('-').last
    volume.attach_to_instance(
      :device => device,
      :instance_id => instance.id
    )
  end
end


def find_instance_by_name name, client
  instance = client.describe_instances(
  filters:[ {
    name: 'tag-value',
    values: [ name ]
    }]
  )

  if instance.first.reservations.empty?
    raise "Can't find #{name}"
  end

  instance_id = instance.reservations[0].instances[0].instance_id
  Aws::EC2::Instance.new(instance_id, :region => 'us-west-2')
end


desired_instance_names = ARGV
if desired_instance_names.empty?
  puts "Input the name of the instances you want to fix yo."
  exit
end

credentials = Aws::Credentials.new(
  ENV['AWS_ACCESS_KEY'],
  ENV['AWS_SECRET_KEY']
)


ec2 = Aws::EC2::Resource.new(
  region: 'us-west-2',
  credentials: credentials
)


ARGV.each do |server|
  instance = find_instance_by_name server, ec2.client
  stop_mongo instance
  #binding.pry
  snapshots = snapshot_volumes instance
  #binding.pry
  new_volumes = create_gp2_from_snapshots(snapshots, ec2.client, instance.placement.availability_zone)
  detach_and_attach instance, new_volumes
  start_mongo instance
end
