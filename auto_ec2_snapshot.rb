#!/usr/bin/env ruby
# Description: This script will manage snapshots of the volumes attached to the given instances.
#              Snapshots will be taken first, then snapshots of those volumes will be deleted if past retention period.
# Requirements: Ruby >= 2.0
#               aws-sdk
#               Configured aws profile

require 'optparse'

# Strip the "=" symbol, then check the value and return nil if the value is empty or nil, otherwise return the value
def checkFlagValue(flag,value)
   # Remove the = symbol, which OptionParser leaves there if you use the shortflag (-p)
  return nil if value.nil?
  value=value.gsub('=','')
  if value.empty?
  	return nil
  end
  return value
end

arguments = Hash.new
## required arguments should be set to nil by default
arguments['profile'] = nil
arguments['region'] = 'us-east-1' # Default region to use if one isn't passed in
arguments['retention_days'] = 3 # How many days to keep snapshots
arguments['dry_run'] = false
arguments['instances'] = []

Options = OptionParser.new do |opt|
	opt.on('--profile PROFILE',"The AWS profile to connect to.") do |o|
		arguments['profile']=checkFlagValue('profile',o)
	end
	opt.on('--region [REGION]','The AWS region to use.') do |o|
		arguments['region'] = checkFlagValue('region',o)
	end
	opt.on('--retention-days [DAYS]','The number of days to hold the snapshots.') do |o|
		arguments['retention_days'] = checkFlagValue('retention_days',o)
	end
	opt.on('--instance-ids INSTANCES','Comma separated list of instance ids.') do |o|
		arguments['instances'] = o.split(",")
	end
	opt.on('--[no-]dry-run','Test rather than actually running.') do |o|
		arguments['dry_run'] = true
	end
opt.parse!
end

def usage(optional_message = nil)
	unless optional_message.nil?
    	puts optional_message
  	end
	puts Options.help
	exit 1
end

# make sure we have the required arguments
arguments.each do |key,value|
	usage("Missing required argument --#{key}") if value.nil?
end

# Load in our aws_helper functions
require_relative 'aws_helper.rb'

credentials = loadProfile(arguments['profile'])  
unless credentials.nil?
  client = createEC2Client(arguments['region'],credentials)
end

tag_name_completed='ff:snapshot:complete'
tag_name_expiration='ff:snapshot:expiration'
tag_name_dae='ff:snapshot:delete_after_expiration'

instances={}
if arguments['instances'].size > 0
	instances = {instance_ids: arguments['instances']}
end

results = client.describe_instances(
			instances,
			{filters:[
				{name:'instance-state-name',values:['running']} 
			]}
			)
# loop through the results to pick out the instances we care to backup.
results.reservations.each do |r|
	r.instances.each do |i|
		instance_name=''
		skip_instance = false
		i.tags.each do |t|
#			puts "\t "+t.key+" : "+t.value
			 if t.key=='aws:autoscaling:groupName'
			 	# Skip instances in auto scaling groups
				skip_instance = true
				break
			 end
			if t.key=='Name'
			  if t.value.empty?
			  	puts "Warning: Instance ID #{i.instance_id} has no Name tag. Using #{i.instance_id} for the snapshot name."
			  	instance_name=i.instance_id
			  elsif t.value.include? 'bamboo'
			  	# Skip bamboo instances
				skip_instance = true
				break
			  else
			  	instance_name=t.value
			  end
			end
		end
		next if skip_instance
		# loop through the block devices attached to this instance
		i.block_device_mappings.each do |b|
			if b.ebs.status != "attached"
				puts "NOTICE: Skipping volume_id #{b.ebs.volume_id} becaues it is in a #{b.ebs.status} state."
				next
			end
			# Take the snapshot of the volume. Use the instance_name value as a default description
			message = "Taking snapshot of #{b.ebs.volume_id} attached to instance id: #{i.instance_id} named: #{instance_name}"
			if arguments['dry_run']
				puts "DRY RUN: Would be #{message}"
				next
			end
			puts "#{message}"
			snapshot = createEBSSnapshot(client,instance_name,b.ebs.volume_id)
			if snapshot.snapshot_id.empty?
				puts "ERROR: snapshot_id was nil for volume #{b.ebs.volume_id}"
				next
			end
			now = Time.now.utc
			exp = Time.at(now.to_i + (arguments['retention_days'].to_i * 24 * 60 * 60)).utc
			# tag the snapshot so that we can easily filter for these tags for pruning
			client.create_tags({resources:[snapshot.snapshot_id],tags:[
				{key:tag_name_completed,value:"#{now}"},
				{key:tag_name_expiration,value:"#{exp}"},
				{key:tag_name_dae,value:'true'}
				]})
		end # end looping through block devices
	end # end looping through instances
end # end looping through reservations


# Prune snapshots that are past the expiration date
now = Time.now.to_i
filters = [{name:'status',values:['completed']},
	# make sure this snapshot should be managed by this script.
	{name:'tag:ff:snapshot:delete_after_expiration',values:['true','yes','1'] },
	# make sure there is an expires tag on the snapshot
	{name:'tag-key',values:[tag_name_expiration]}
	]
snapshots = client.describe_snapshots({filters: filters}).snapshots
snapshots.each do |s|
	s.tags.each do |t|
		if t.key==tag_name_expiration
			begin
				s_expires = DateTime.parse(t.value).strftime("%s").to_i
			rescue Exception => e
				puts "WARNING: #{e.message} received for snapshot #{s.snapshot_id}. Make sure it contains a valid expiration date."
    			break
			end
    		if(s_expires < now)
    			message = "Deleting snapshot #{s.snapshot_id} because it expired on #{t.value}"
    			if arguments['dry_run']
    				puts "DRY RUN: Would be #{message}"
    				next
    			end
    			client.delete_snapshot(snapshot_id:s.snapshot_id)
    		end
    		break
		end
	end
end
