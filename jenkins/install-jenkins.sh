#!/bin/bash

sudo docker build -t jenkins-custom:v1 .

#Add certificate for Jenkins on 443 Port

#Cmment this after, this is to renew jenkins cert
# sudo docker-compose down

#This is to run jenins on open ssl, commented as now we are using ALB with ACM

# sudo certbot certonly --standalone --preferred-challenges http -d jenkins.emversity.com \
#  --non-interactive --register-unsafely-without-email --agree-tos

# sudo openssl pkcs12 -export -in /etc/letsencrypt/live/jenkins.emversity.com/fullchain.pem \
#  -inkey /etc/letsencrypt/live/jenkins.emversity.com/privkey.pem -out output_jenkins.p12 \
#  -name opensslcert -password pass:adminkeystorepass

# sudo keytool -importkeystore -noprompt \
#  -alias opensslcert \
#  -srckeystore output_jenkins.p12 -srcstoretype pkcs12 -srcstorepass adminkeystorepass \
#  -destkeystore jenkins_keystore.jks -deststoretype JKS -deststorepass adminkeystorepass


# sudo cp jenkins_keystore.jks /mnt/ebs/jenkins/jenkins_keystore.jks
sudo docker compose up -d
sleep 35
sudo cat /mnt/ebs/jenkins/secrets/initialAdminPassword 2>/dev/null || echo "Initial admin password file not found"
