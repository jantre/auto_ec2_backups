#!/usr/bin/env ruby
# Description:  helper/wrapper functions to AWS API calls,

require 'aws-sdk'

# Load a local profile 
# return the SharedCredentials object or nil
def loadProfile(profile=nil)
  # CAUTION: We are returning if profile is nil because otherwise AWS will try to use "Default" profile
  return nil if profile.nil?
  begin  #ruby syntax equivalant to try
    # Read the credentials from the given profile
    credentials = Aws::SharedCredentials.new(profile_name: profile)
  # make sure profile exists before proceeding
  rescue  Exception => e # ruby syntax equivalant to catch
    puts "\e[31mERROR: #{e.message}\e[0m"
    exit 1
  end
  return credentials if credentials.loadable?
  puts "\e[31mERROR: Credentials are not loadable. Make sure you have ~/.aws configured correctly.\e[0m"
  return nil 
end

# helper function to return a new RDS client
def createRDSClient(region,credentials)
  begin
    return Aws::RDS::Client.new(region: region,credentials: credentials)
  rescue Exception => e
    puts "\e[31mCould not create new RDS client."
    puts "#{e.message}\e[0m"
    exit 1
  end
end

# helper function to return a new EC2 client
def createEC2Client(region,credentials)
  begin
    return Aws::EC2::Client.new(region: region,credentials: credentials)
  rescue Exception => e
    puts "\e[31mCould not create new EC2 client"
    puts "#{e.message}\e[0m"
    exit 1
  end
end

# http://docs.aws.amazon.com/sdkforruby/api/Aws/EC2/Client.html#create_snapshot-instance_method
# Helper function to create a snapshot of an EBS volume
def createEBSSnapshot(client=nil,description='',volume_id=nil)
  return false if volume_id.nil? || client.nil?
  # Fetch the Volume Name. This will be used in the description of the snapshot
  resp = client.describe_volumes({dry_run: false, volume_ids: [volume_id] })
  resp.volumes[0].tags.each do |t|
    if t.key=='Name'
      description = t.value unless t.value.empty?
      break
    end
  end
  # puts "Taking snapshot of volume #{volume_id}..."
  return client.create_snapshot({
    dry_run: false,
    volume_id: volume_id,
    description: description
  })
end

# Delete a snapshot of an ebs volume
# Can accept a single snapshot or an array of snapshots to delete.
def deleteEBSSnapshot(client=nil,snapshots_to_delete=[],dry_run=true)
  return false if client.nil?
  unless snapshots_to_delete.instance_of? Array
    snapshots_to_delete = [snapshots_to_delete]
  end
  snapshots_to_delete.each do |snapshot|
    if dry_run
      printf "\e[33m\"Delete snapshot #{snapshot}?\" (y/n)? \e[0m"
      prompt = STDIN.gets.chomp
      next unless prompt == "y"
    end
    print "Deleting ec2 snapshot #{snapshot}..."
    begin
    # delete_snapshot API has no response
    client.delete_snapshot({
        dry_run: dry_run,
        snapshot_id: snapshot
    })
      puts "\e[32msuccess\e[0m"
    rescue Exception => e
      puts "\e[31mfailed - #{e.message}\e[0m"
    end
  end
  return true
end

# helper function to create RDS Snapshots
# return the response on success, otherwise false.
def createRDSSnapshot(client=nil,db_instance=nil,snapshot_name=nil,tags=[])
  return false if db_instance.nil? || client.nil?
  if snapshot_name.nil?
    snapshot_name="#{db_instance}-#{Time.now.to_i}"
  end
  unless tags.instance_of? Array
    puts "\e[31mtags must be an Array\e[0m"
    return false
  end
  begin
    puts "\e[32mTaking snapshot of db instance #{db_instance}. Snapshot will be named #{snapshot_name}\e[0m"
    resp = client.create_db_snapshot({
      db_snapshot_identifier: snapshot_name,
      db_instance_identifier: db_instance,
      tags: tags
    })
  rescue Exception => e
    puts "\e[31m#{e.message}\e[0m"
    return false
  end
  return resp
end

def deleteRDSSnapshot(client=nil,snapshots_to_delete=[],prompt=true)
  return false if client.nil?
  unless snapshots_to_delete.instance_of? Array
    snapshots_to_delete = [snapshots_to_delete]
  end
  snapshots_to_delete.each do |snapshot|
    if prompt
      printf "\e[33m\"Delete snapshot #{snapshot}?\" (y/n)? \e[0m"
      prompt = STDIN.gets.chomp
      next unless prompt == "y"
    end
    print "Deleting snapshot #{snapshot}..."
    begin
    # delete_snapshot API has no response
    client.delete_db_snapshot({
        db_snapshot_identifier: snapshot
    })
      puts "\e[32msuccess\e[0m"
    rescue Exception => e
      puts "\e[31mfailed - #{e.message}\e[0m"
    end
  end
  return true
end
