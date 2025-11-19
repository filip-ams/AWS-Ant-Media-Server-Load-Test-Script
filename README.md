# AWS Ant Media Server Load Test Script

This Bash script automates the deployment and load testing of **Ant Media Server** on AWS EC2 instances. It launches both an Ant Media Server instance and a load tester instance, optionally configures Adaptive Bitrate (ABR) streaming, and provides an interactive interface for running RTMP load tests.

## Features

- **Automated EC2 Deployment**: Launches Ant Media Server and Load Tester instances with user-specified instance types.  
- **GPU Detection**: Automatically detects GPU instance types and installs NVIDIA CUDA drivers if needed.  
- **Adaptive Bitrate (ABR) Presets**: Optionally apply ABR presets (1080p, 720p, 480p, 360p) to the WebRTCAppEE application.  
- **Interactive RTMP Load Testing**: Upload local `.mp4` video files and run multiple publishers to test server performance.  
- **SSH Setup and Automation**: Installs necessary dependencies on both Ant Media and Load Tester instances.  
- **EC2 Instance Management**: Waits for instances to be ready, checks status, and optionally terminates instances after testing.  
- **Test Summaries**: Collects CPU usage statistics and generates a summary file for each test run. (Work in progress) 

## Pre-requisites

Before using this script, make sure you have the following:

1. **AWS CLI Installed & Configured**
   - Install the [AWS CLI](https://aws.amazon.com/cli/) on your local machine.
   - Run `aws configure` to set up your access key, secret key, default region, and output format.

2. **IAM Permissions**
   - The IAM user you are using must have sufficient permissions to:
     - Launch and terminate EC2 instances
     - Access key pairs
     - Manage security groups
     - Reboot instances
   - Without proper permissions, the script will fail.

3. **Ant Media License**
   - A valid Ant Media Server license key is required. Add it to the `AMS_LICENSE` variable in the configuration section.

4. **Local Files**
   - Ensure your EC2 private key `.pem` file is accessible and has proper permissions (`chmod 400`).

5. **Video Files**
   - For load testing, have `.mp4` video files in the current directory to upload to the Load Tester instance.


## Configuration - UPDATE BEFORE USE

Before running the script, update the following variables in the configuration section:

| Variable        | Description |
|-----------------|-------------|
| `AMI_ID`        | The Amazon Machine Image ID to launch your EC2 instances. Replace with a valid AMI ID for your AWS region. |
| `KEY_NAME`      | Name of the EC2 key pair you created in AWS. This key is used for SSH access to your instances. |
| `SSH_KEY_PATH`  | Path to your private `.pem` file corresponding to `KEY_NAME`. Ensure the file permissions are secure (`chmod 400`). |
| `SECURITY_GROUP`| The ID of the security group that allows required ports (e.g., 22 for SSH, 1935 for RTMP). |
| `REGION`        | AWS region where your instances will be launched (e.g., `eu-west-2`). |
| `APP_NAME`      | Default application name on Ant Media Server. If you do not plan to use ABR, you can leave this as `LiveApp`. |
| `STREAM_ID`     | Default stream identifier for load testing. |
| `OUTPUT_DIR`    | Directory where test logs and summaries will be saved locally. |
| `AMS_LICENSE`   | Your Ant Media Server license key (required for installation). |

