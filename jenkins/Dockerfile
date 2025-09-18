#Custom docker file for jenkins
#Will be made from jenkins/jenkins:lts

# Use the official Jenkins LTS image as the base image
FROM jenkins/jenkins:lts

# Switch to the root user to install additional tools
USER root

# Install Helm
RUN curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 && \
    chmod +x get_helm.sh && \
    ./get_helm.sh && \
    rm get_helm.sh

# Install Maven
RUN apt-get update && \
    apt-get install -y maven

# Install Docker

RUN apt-get update && \
    apt-get install -y apt-transport-https ca-certificates curl software-properties-common && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu focal stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y docker-ce docker-ce-cli containerd.io && \
    usermod -aG docker jenkins

# Install necessary tools and dependencies
RUN apt-get update && \
    apt-get install -y wget unzip && \
    rm -rf /var/lib/apt/lists/*

# Install Jenkins CLI


# Download and install the Jenkins CLI JAR
RUN wget https://repo.jenkins-ci.org/releases/org/jenkins-ci/main/cli/2.311/cli-2.311.jar -O /usr/local/bin/jenkins-cli.jar && \
    chmod +x /usr/local/bin/jenkins-cli.jar

# Install jq
RUN apt-get update && apt-get install -y jq

# Install yq
RUN wget https://github.com/mikefarah/yq/releases/download/v4.13.2/yq_linux_amd64 -O /usr/local/bin/yq && chmod +x /usr/local/bin/yq

# Install Terraform
ENV TERRAFORM_VERSION="1.5.7"
RUN wget https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip && \
    unzip terraform_${TERRAFORM_VERSION}_linux_amd64.zip && \
    mv terraform /usr/local/bin/ && \
    rm terraform_${TERRAFORM_VERSION}_linux_amd64.zip

# Install AWS CLI
RUN apt-get update && \
    apt-get install -y awscli

# Update packages and install pip3 and boto3
RUN apt-get update && \
    apt-get install -y python3-pip && \
    apt install -y python3-boto3 && \
    pip3 install gspread --break-system-packages && \
    pip3 install google-auth --break-system-packages && \
    pip3 install requests --break-system-packages && \
    pip3 install google-cloud-batch --break-system-packages && \
    pip3 install google-api-python-client --break-system-packages && \
    pip3 install urllib3 --break-system-packages && \
    rm -rf /var/lib/apt/lists/*

RUN echo "deb http://packages.cloud.google.com/apt cloud-sdk-stretch main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list \
    && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - \
    && apt-get update -y && apt-get install google-cloud-sdk -y \
    && PATH=$PATH:/root/google-cloud-sdk/bin


RUN apt-get update && \
    apt-get install -y zip

# Switch back to the Jenkins user
USER jenkins

