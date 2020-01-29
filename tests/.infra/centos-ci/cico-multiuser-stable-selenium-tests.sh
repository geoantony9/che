#!/usr/bin/env bash
# Copyright (c) 2018 Red Hat, Inc.
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Eclipse Public License v1.0
# which accompanies this distribution, and is available at
# http://www.eclipse.org/legal/epl-v10.html
set -e

echo "========Starting nigtly test job $(date)========"

source tests/.infra/centos-ci/functional_tests_utils.sh
source .ci/cico_common.sh

installDependencies

export CHE_INFRASTRUCTURE=openshift
export PATH=$PATH:/opt/rh/rh-maven33/root/bin



installKVM
installDependencies
installCheCtl
installAndStartMinishift
loginToOpenshiftAndSetDevRole
chectl server:start -a operator -p openshift --k8spodreadytimeout=360000 --chenamespace=eclipse-che
createTestUserAndObtainUserToken
installDockerCompose
defindCheRoute
mvn clean install -pl :che-selenium-test -am -DskipTests=true -U
cd tests/legacy-e2e/che-selenium-test
bash selenium-tests.sh --threads=4 --host=${CHE_ROUTE} --port=80 --multiuser

#createTestWorkspaceAndRunTest
#archiveArtifacts "che-nightly"

