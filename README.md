# Synopsis

This script is a useful backup solution to EBS volumes attached to running EC2 instances.
It will create snapshots of volumes attached to the EC2 instances specified and it will delete snapshots that have past their retention period.

# Requirements
* Ruby >= 2.0
* aws-sdk (Version 2)
* Configured AWS profile (~/.aws/credentials)
* IAM User with the permissions required for this script (See below)

# Setup
### 1. Create an IAM User
Attach the following custom policy to the user.
```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "ec2:CreateSnapshot",
                "ec2:CreateTags",
                "ec2:DeleteSnapshot",
                "ec2:DescribeInstances",
                "ec2:DescribeSnapshots",
                "ec2:DescribeVolumes"
            ],
            "Effect": "Allow",
            "Resource": "*"
        }
    ]
}
```

### 2. Configure an AWS Profile.
On the instance you plan on running this script you can create a profile by running `aws configure` and follow the instructions.
OR 
If you don't have aws-cli installed and you don't want to install it you can do the following.
`mkdir ~/.aws`
`vi ~/.aws/credentials`
Use the following as a template. "default" is the name of the profile in this example.
Replace access_key, key_id and region with yours.
```
[default]
region = us-east-1
aws_access_key_id = ************************
aws_secret_access_key = *************************************
```
### 3. Install the aws-sdk and Ruby
`yum -y install ruby22 aws-sdk`

# Usage
```
Usage: auto_ec2_snapshot [options]
        --profile PROFILE            The AWS profile to connect to.
        --region [REGION]            The AWS region to use.
        --retention-days [DAYS]      The number of days to hold the snapshots.
        --instance-ids INSTANCES     Comma separated list of instance ids.
        --[no-]dry-run               Test rather than actually running.
```
### Testing
Use the --dry-run flag to get output of what would happen without any action being taken.
`./auto_ec2_snapshot.rb --profile default`


### Examples
###### Back up volumes attached to all running EC2 instances in your "production" Profile.
`./auto_ec2_snapshot.rb --profile production --retention-days 7`
###### Back up volumes attached to the specified instances
`./auto_ec2_snapshot.rb --profile default --retention-days 3 --instance-ids i-123456789,i-abcdefghi`

