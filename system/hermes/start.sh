#!/bin/bash
# Start a gateway and dashboard for each profile in parallel.
# Container exits when any process exits; Docker's restart policy brings everything back up.
hermes --profile personal gateway run &
hermes --profile family gateway run &
hermes --profile stonkbot gateway run &
hermes --profile personal dashboard --host 0.0.0.0 --port 9119 --insecure --no-open &
hermes --profile family dashboard --host 0.0.0.0 --port 9121 --insecure --no-open &
hermes --profile stonkbot dashboard --host 0.0.0.0 --port 9122 --insecure --no-open &
# Exit with the status of whichever process finishes first
wait -n
exit $?