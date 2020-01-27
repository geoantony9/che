#!/usr/bin/env bash
# Copyright (c) 2018 Red Hat, Inc.
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Eclipse Public License v1.0
# which accompanies this distribution, and is available at
# http://www.eclipse.org/legal/epl-v10.html
set +e

echo "========Starting nigtly test job $(date)========"

source tests/.infra/centos-ci/functional_tests_utils.sh
source .ci/cico_common.sh

setupEnvs
checkAllCreds
installDependencies
installAndStartMinishift
loginToOpenshiftAndSetDevRople
installCheCtl
deployCheIntoCluster
createTestUserAndObtainUserToken
if createTestWorkspaceAndRunTest; then
    echo '========Tests passed successfully========'
    archiveArtifacts
    echo "========Finishing nigtly test job $(date)========"
else
    archiveArtifacts
    echo "========Finishing nigtly test job $(date)========"
    set -x
    exit 1
fi


