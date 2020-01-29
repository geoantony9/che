#!/usr/bin/env bash
# Copyright (c) 2020 Red Hat, Inc.
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Eclipse Public License v1.0
# which accompanies this distribution, and is available at
# http://www.eclipse.org/legal/epl-v10.html

set -e
set +x

source tests/.infra/centos-ci/functional_tests_utils.sh

echo "****** Starting RH-Che PR check $(date) ******"
export BASEDIR=$(pwd)
echo $BASEDIR
export PATH=$PATH:/opt/rh/rh-maven33/root/bin
export PR=15818
export TAG=PR-${PR}

setupEnvs
installDependencies
installDockerCompose

mvn clean install -Pintegration
bash dockerfiles/che/build.sh --organization:quay.io/eclipse --tag:${TAG} --dockerfile:Dockerfile

docker login -u "${QUAY_ECLIPSE_CHE_USERNAME}" -p "${QUAY_ECLIPSE_CHE_PASSWORD}" "quay.io"
docker push "quay.io/eclipse/che-server:${TAG}"

installKVM
installAndStartMinishift
loginToOpenshiftAndSetDevRole
installCheCtl

echo "Deploy Eclipse Che"
cd /tmp
wget https://raw.githubusercontent.com/eclipse/che-operator/master/deploy/crds/org_v1_che_cr.yaml -O custom-resource.yaml
sed -i "s@server:@server:\n    customCheProperties:\n      CHE_LIMITS_USER_WORKSPACES_RUN_COUNT: '-1'@g" /tmp/custom-resource.yaml
sed -i "s/customCheProperties:/customCheProperties:\n      CHE_WORKSPACE_AGENT_DEV_INACTIVE__STOP__TIMEOUT__MS: '300000'/" /tmp/custom-resource.yaml
sed -i "s@cheImage: ''@cheImage: 'quay.io/eclipse/che-server'@g" /tmp/custom-resource.yaml
sed -i "s@cheImageTag: 'nightly'@cheImageTag: '${TAG}'@g" /tmp/custom-resource.yaml
cat /tmp/custom-resource.yaml

chectl server:start -a operator -p openshift --k8spodreadytimeout=360000 --listr-renderer=verbose --chenamespace=eclipse-che --che-operator-cr-yaml=/tmp/custom-resource.yaml
oc get checluster -o yaml

echo "Start selenium tests"
export CHE_INFRASTRUCTURE=openshift
CHE_ROUTE=$(oc get route che --template='{{ .spec.host }}')

cd ${BASEDIR}
mvn clean install -pl :che-selenium-test -am -DskipTests=true -U
configureGithubTestUser

#bash tests/legacy-e2e/che-selenium-test/selenium-tests.sh --host=${CHE_ROUTE} --port=80 --multiuser --test=CreateAndDeleteProjectsTest
#bash selenium-tests.sh --threads=4 --host=${CHE_ROUTE} --port=80 --multiuser --test=org.eclipse.che.selenium.dashboard.**
bash selenium-tests.sh --threads=5 --host=${CHE_ROUTE} --port=80 --multiuser

/tmp/oc login -u system:admin
/tmp/oc get events --all-namespaces
/tmp/oc logs deployments/che | true

mkdir -p report
mkdir -p report/site
cp -r tests/legacy-e2e/che-selenium-test/target/site report/site

archiveArtifacts "che-pullrequests-test-temporary"
