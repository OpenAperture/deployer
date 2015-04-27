OpenAperture Deployer
===============
 
[![Build Status](https://semaphoreci.com/api/v1/projects/945259c7-3a47-4bbf-8f62-2939544b3405/403578/badge.svg)](https://semaphoreci.com/perceptive/deployer)

OpenAperture Deployer is a part of the OpenAperture ecosystem responsible for actual
deployment of containerazed applications to the CoreOS cluster.

## Communication with other components
Deployer receives AMQP messages from OpenAperture Orchestrator (through an AMQP broker)
to start the deployment routine.
The AMQP message is getting aknowledged once the entire deployment is finished.
Otherwise, the AMQP broker will re-schedule the deployment, so that it can be
picked up again either by the same or a different Deployer worker.

In addition to aknowledging the message, Deployer sends out an AMQP message,
reporting that the deployment has been successful. It's handled further by Orchestrator.
Also, along the way, there are the progress notifications sent out, which are
supposed to be further handled by OpenAperture Notifications server.

## Configuration

## Format of the AMQP message initiating a deployment
The following Map is expected as AMQP message payload:
```
%{
  container_repo:     "target/repo_docker",
  source_commit_hash: "afdjasdfoiu20493u234i2ok3n4l234",
  workflow_id:        123901823,
  project_name:       "target_app",
  reporting_queue:    "orchestrator"
}
```
