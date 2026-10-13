#!/usr/bin/env bash

# EX_NOHOST (68) includes unexpected ticket-service responses. Retry only ticket
# retrieval after successful notarization; never skip validation or resubmit here.
staple_with_retry() {
    local target="$1"
    local attempt status
    for attempt in 1 2 3; do
        if xcrun stapler staple "$target"; then
            return 0
        else
            status=$?
        fi
        if [[ "$status" != 68 || "$attempt" == 3 ]]; then
            return "$status"
        fi
        echo "Apple ticket retrieval failed (68); retrying after $((attempt * 5)) seconds." >&2
        sleep "$((attempt * 5))"
    done
}
