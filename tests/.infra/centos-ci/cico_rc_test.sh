#!/usr/bin/env bash
# Copyright (c) 2018 Red Hat, Inc.
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Eclipse Public License v1.0
# which accompanies this distribution, and is available at
# http://www.eclipse.org/legal/epl-v10.html

set -e
set +x

echo "****** Starting RH-Che RC check $(date) ******"

total_start_time=$(date +%s)
export BASEDIR=$(pwd)
export RELEASE_TAG=7.7.1
export RELEASE_VERSION=7.7.1

 eval "$(./env-toolkit load -f jenkins-env.json \
                              CHE_BOT_GITHUB_TOKEN \
                              CHE_MAVEN_SETTINGS \
                              CHE_GITHUB_SSH_KEY \
                              ^BUILD_NUMBER$ \
                              CHE_OSS_SONATYPE_GPG_KEY \
                              CHE_OSS_SONATYPE_PASSPHRASE \
                              QUAY_ECLIPSE_CHE_USERNAME \
                              QUAY_ECLIPSE_CHE_PASSWORD)"

source tests/.infra/centos-ci/functional_tests_utils.sh

echo "Installing dependencies:"
start=$(date +%s)
installDependencies
stop=$(date +%s)
install_dep_duration=$(($stop - $start))

echo "Install maven"
curl -L http://mirrors.ukfast.co.uk/sites/ftp.apache.org/maven/maven-3/3.3.9/binaries/apache-maven-3.3.9-bin.tar.gz | tar -C /opt -xzv
export M2_HOME=/opt/apache-maven-3.3.9
export M2=$M2_HOME/bin
export PATH=$M2:/tmp:$PATH
export JAVA_HOME=/usr/
mvn --version

echo "Install docker compose"
sudo curl -L "https://github.com/docker/compose/releases/download/1.25.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

echo "Installing all dependencies lasted $install_dep_duration seconds."

installKVM
installAndStartMinishift

oc login -u system:admin
oc adm policy add-cluster-role-to-user cluster-admin developer
oc login -u developer -p pass

installCheCtl

echo "Deploy Eclipse Che"

cd /tmp

echo "Patch custom-resource.yaml"

wget https://raw.githubusercontent.com/eclipse/che-operator/master/deploy/crds/org_v1_che_cr.yaml -O custom-resource.yaml
sed -i "s@server:@server:\n    customCheProperties:\n      CHE_LIMITS_USER_WORKSPACES_RUN_COUNT: '-1'@g" /tmp/custom-resource.yaml
sed -i "s/customCheProperties:/customCheProperties:\n      CHE_WORKSPACE_AGENT_DEV_INACTIVE__STOP__TIMEOUT__MS: '300000'/" /tmp/custom-resource.yaml
sed -i "s@identityProviderImage: 'eclipse/che-keycloak:nightly'@identityProviderImage: 'quay.io/eclipse/che-keycloak:$RELEASE_TAG'@g" /tmp/custom-resource.yaml
sed -i "s@cheImage: ''@cheImage: 'quay.io/eclipse/che-server'@g" /tmp/custom-resource.yaml
sed -i "s@cheImageTag: 'nightly'@cheImageTag: '$RELEASE_TAG'@g" /tmp/custom-resource.yaml
sed -i "s@devfileRegistryImage: 'quay.io/eclipse/che-devfile-registry:nightly'@devfileRegistryImage: 'quay.io/eclipse/che-devfile-registry:$RELEASE_VERSION'@g" /tmp/custom-resource.yaml
sed -i "s@pluginRegistryImage: 'quay.io/eclipse/che-plugin-registry:nightly'@pluginRegistryImage: 'quay.io/eclipse/che-plugin-registry:$RELEASE_VERSION'@g " /tmp/custom-resource.yaml
cat /tmp/custom-resource.yaml

chectl server:start -a operator -p openshift --k8spodreadytimeout=360000 --listr-renderer=verbose --chenamespace=eclipse-che --che-operator-cr-yaml=/tmp/custom-resource.yaml
oc get checluster -o yaml

CHE_ROUTE=$(oc get route che --template='{{ .spec.host }}')
curl -vL $CHE_ROUTE

echo "Start selenium tests"

cd ${BASEDIR}
set +x
cp /usr/local/bin/oc /tmp
export CHE_INFRASTRUCTURE=openshift

# add github oauth
kc_container_id=$(docker ps | grep keycloak_keycloak-1 | cut -d ' ' -f1)
docker exec -i $kc_container_id sh -c "keycloak/bin/kcadm.sh create identity-provider/instances -r che -s alias=github -s providerId=github -s enabled=true -s storeToken=true -s addReadTokenRoleOnCreate=true -s 'config.useJwksUrl="true"' -s config.clientId=$CHE_MULTI_USER_GITHUB_CLIENTID_OCP -s config.clientSecret=$CHE_MULTI_USER_GITHUB_SECRET_OCP -s 'config.defaultScope="repo,user,write:public_key"' --no-config --server http://localhost:8080/auth --user admin --password admin --realm master"

echo "Configure GitHub test users"
mkdir -p ${BASEDIR}/che_local_conf_dir
export CHE_LOCAL_CONF_DIR=${BASEDIR}/che_local_conf_dir/
rm -f ${BASEDIR}/che_local_conf_dir/selenium.properties
echo "github.username=che6ocpmulti" >> ${BASEDIR}/che_local_conf_dir/selenium.properties
echo "github.password=CheMain2017" >> ${BASEDIR}/che_local_conf_dir/selenium.properties
echo "github.auxiliary.username=iedexmain1" >> ${BASEDIR}/che_local_conf_dir/selenium.properties
echo "github.auxiliary.password=CodenvyMain15" >> ${BASEDIR}/che_local_conf_dir/selenium.properties
export CHE_LOCAL_CONF_DIR=${BASEDIR}/che_local_conf_dir/

#build selenium module
echo "Build selenium module"
mvn clean install -pl :che-selenium-test -am -DskipTests=true -U

cd tests/legacy-e2e/che-selenium-test
bash selenium-tests.sh --threads=1 --host=${CHE_ROUTE} --port=80 --multiuser --test=CreateAndDeleteProjectsTest
#bash selenium-tests.sh --threads=4 --host=${CHE_ROUTE} --port=80 --multiuser --test=org.eclipse.che.selenium.dashboard.**
#bash selenium-tests.sh --threads=5 --host=${CHE_ROUTE} --port=80 --multiuser

JOB_NAME=rc-integration-tests
DATE=$(date +"%m-%d-%Y-%H-%M")
echo "Archiving artifacts from ${DATE} for ${JOB_NAME}/${BUILD_NUMBER}"
cd ${BASEDIR}
pwd
ls -la ./artifacts.key
chmod 600 ./artifacts.key
chown $(whoami) ./artifacts.key
mkdir -p ./che/${JOB_NAME}/${BUILD_NUMBER}
cp -R ${BASEDIR}/tests/legacy-e2e/che-selenium-test/target/site ./che/${JOB_NAME}/${BUILD_NUMBER}/ | true
rsync --password-file=./artifacts.key -Hva --partial --relative ./che/${JOB_NAME}/${BUILD_NUMBER} devtools@artifacts.ci.centos.org::devtools/
