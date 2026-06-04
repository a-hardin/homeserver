#!/bin/bash
# Start a gateway for each profile in parallel.
# Container exits when the first gateway process exits; Docker's restart policy
# brings everything back up — no individual process supervision needed.
hermes --profile personal gateway run &
hermes --profile family gateway run &
hermes --profile stonkbot gateway run &
# Exit with the status of whichever process finishes first
wait -n
exit $?