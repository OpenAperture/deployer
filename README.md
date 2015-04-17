OpenAperture Deployer
===============

[![Build Status](https://semaphoreci.com/api/v1/projects/9e9fbe62-7219-4d14-b272-d3908da9130b/395713/badge.svg)](https://semaphoreci.com/perceptive/deployer)

## WARNING: THIS IS A WORK IN PROGRESS, no guarantee that it will work correctly, if at all at this moment.

OpenAperture Deployer is a part of the OpenAperture ecosystem responsible for retrieving the
source code of a target application, its pre-configuration and further deployment to
the CoreOS cluster.

## Communication with other components
Deployer receives AMQP messages from Orchestrator to start the deployment routine.
The AMQP message is getting aknowledged once the entire deployment is finished.
Otherwise, the AMQP broker will re-schedule the deployment, so that it can be
picked up again either by the same or a different Deployer worker.

In addition to aknowledging the broker, Deployer sends out a message to the AMQP
broker, reporting that the deployment has been successful. That message is then
delivered to Orchestrator which tracks the entire workwlow process.

## Format of the AMQP message initiating deployment
```
%{
  container_repo:     "target/repo_docker",
  source_commit_hash:  "afdjasdfoiu20493u234i2ok3n4l234",
  workflow_id:         123901823
  project_name:        "target_app",
  product:             "target_product",
  product_environment: "target_environment",
  source_repo:         "target/repo"                       # optional
}
```
