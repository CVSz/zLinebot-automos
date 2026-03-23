package main

import rego.v1

deny contains msg if {
  input.kind == "Deployment"
  some container in input.spec.template.spec.containers
  not container.securityContext.runAsNonRoot
  msg := sprintf("%s: container %s must set securityContext.runAsNonRoot=true", [input.metadata.name, container.name])
}

deny contains msg if {
  input.kind == "Deployment"
  some container in input.spec.template.spec.containers
  not container.resources.requests.cpu
  msg := sprintf("%s: container %s must define resources.requests.cpu", [input.metadata.name, container.name])
}

deny contains msg if {
  input.kind == "Deployment"
  some container in input.spec.template.spec.containers
  not container.resources.limits.memory
  msg := sprintf("%s: container %s must define resources.limits.memory", [input.metadata.name, container.name])
}

deny contains msg if {
  input.kind == "Deployment"
  some container in input.spec.template.spec.containers
  not contains(container.image, "@sha256:")
  msg := sprintf("%s: container %s image must be digest pinned", [input.metadata.name, container.name])
}
