################################################################################
#                                       Neuron
################################################################################

This is the node in the brain project.  It uses the Smash::CloudPowers module,
which is a sub-module in git, as a wrapper around the AWS SDK.

## Configuration ##
1. $ cp .neuron.env.example .neuron.env
2. add the required values to .neuron.env

## Running ##
For testing:
$ ruby neuron.rb

For production:
/bin/bash ./build