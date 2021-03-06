#!/usr/bin/env bash
#
# Copyright 2020 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# E2E tests for helm_inflator.

set -eo pipefail
DIR="$(dirname "$0")"
# shellcheck source=tests/common.sh
source "$DIR"/common.sh

helm_testcase "kpt_helm_inflator_imperative_expected_args"
kpt fn source example-configs |
  kpt fn run --as-current-user --mount type=bind,src="$(pwd)/${CHARTS_SRC}",dst=/source --image gcr.io/kpt-functions/helm-inflator:"${TAG}" -- name=expected-args local-chart-path=/source/redis >out.yaml
assert_contains_string out.yaml "expected-args"

testcase "kpt_helm_inflator_declarative_example"
# TODO: Remove error handling once kpt pkg get shows errors gracefully https://github.com/GoogleContainerTools/kpt/issues/838
kpt pkg get "$CATALOG_REPO"/examples/helm-inflator . || true
# Use proper image tag
sed -e "s/image: gcr.io\/kpt-functions\/helm-inflator/image: gcr.io\/kpt-functions\/helm-inflator:${TAG}/" -i helm-inflator/local-configs/fn-config.yaml
kpt fn run helm-inflator/local-configs --mount type=bind,src="$(pwd)"/helm-inflator/helloworld-chart,dst=/source --as-current-user
assert_contains_string helm-inflator/local-configs/deployment_chart-helloworld-chart.yaml "name: chart-helloworld-chart"

helm_testcase "kpt_helm_inflator_declarative_fn_path"
cat >fc.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-config
  annotations:
    config.k8s.io/function: |
      container:
        image: gcr.io/kpt-functions/helm-inflator:${TAG}
    config.kubernetes.io/local-config: "true"
data:
  name: extra-args
  local-chart-path: /source
  --values: /source/values-production.yaml
EOF
kpt fn source example-configs |
  kpt fn run --mount type=bind,src="$(pwd)/${CHARTS_SRC}/redis",dst=/source --fn-path fc.yaml --as-current-user >out.yaml
assert_contains_string out.yaml "name: extra-args-redis-master"

helm_testcase "kpt_helm_inflator_imperative_pipeline"
kpt fn source example-configs |
  kpt fn run --mount type=bind,src="$(pwd)/${CHARTS_SRC}",dst=/source --image gcr.io/kpt-functions/helm-inflator:"${TAG}" --as-current-user -- local-chart-path=/source/zookeeper name=my-zookeeper | 
  kpt fn run --mount type=bind,src="$(pwd)/${CHARTS_SRC}",dst=/source --image gcr.io/kpt-functions/helm-inflator:"${TAG}" --as-current-user -- name=my-redis local-chart-path=/source/redis |
  kpt fn sink .
assert_dir_exists default
assert_contains_string default/service_my-zookeeper.yaml "name: my-zookeeper"
assert_contains_string default/secret_my-redis.yaml "name: my-redis"

helm_testcase "kpt_helm_inflator_remote_imperative_expected_args"
kpt fn source example-configs |
kpt fn run --network --image gcr.io/kpt-functions/helm-inflator:"${TAG}" -- chart=bitnami/redis chart-repo=bitnami chart-repo-url=https://charts.bitnami.com/bitnami name=expected-args >out.yaml
assert_contains_string out.yaml "expected-args"

helm_testcase "kpt_helm_inflator_remote_declarative_fn_path"
cat >fc.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-config
  annotations:
    config.k8s.io/function: |
      container:
        image: gcr.io/kpt-functions/helm-inflator:${TAG}
        network: true
    config.kubernetes.io/local-config: "true"
data:
  name: extra-args
  chart: bitnami/redis
  chart-repo: bitnami
  chart-repo-url: https://charts.bitnami.com/bitnami
EOF
kpt fn source example-configs |
kpt fn run --network --fn-path fc.yaml >out.yaml
assert_contains_string out.yaml "name: extra-args-redis-master"

helm_testcase "kpt_helm_inflator_remote_imperative_pipeline"
kpt fn source example-configs |
  kpt fn run --network --image gcr.io/kpt-functions/helm-inflator:"${TAG}" -- chart=bitnami/zookeeper chart-repo=bitnami chart-repo-url=https://charts.bitnami.com/bitnami name=my-zookeeper | 
  kpt fn run --network --image gcr.io/kpt-functions/helm-inflator:"${TAG}" -- chart=bitnami/redis chart-repo=bitnami chart-repo-url=https://charts.bitnami.com/bitnami name=my-redis |
  kpt fn sink .
assert_dir_exists default
assert_contains_string default/service_my-zookeeper.yaml "name: my-zookeeper"
assert_contains_string default/secret_my-redis.yaml "name: my-redis"
