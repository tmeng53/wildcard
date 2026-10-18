#!/bin/bash
# Cloud environment setup script: paste into the environment's settings.
# Template from sponge-ai-lab/engineering-skills (cloud-test-environment skill).
# Pre-pulls the test images into the cached environment, so sessions don't pull them.
nohup dockerd >/tmp/dockerd.log 2>&1 &
for _ in $(seq 1 60); do docker info >/dev/null 2>&1 && break; sleep 0.5; done
docker pull postgres:16.4
# docker pull <each other image in docker-compose.yml>
# docker pull testcontainers/ryuk:<version>   # if tests use Testcontainers
