#!/bin/bash
#
# Shared PBS / ian resource selection.
# Pure MPI: one CPU per MPI rank, one thread per rank.
# Automatic selection uses the supplied queue limits, not congestion.

configure_stage_resources() {
    [[ "${SYSTEM_KEY:-}" == "PBS_ian" ]] || return 0

    local stage="$1"
    local quiet="${2:-}"
    local name suffix
    local nodes ranks walltime mode manual
    local seconds total queue max_seconds max_nodes max_cpus
    local selected=""

    case "$stage" in
        STATIC|DEGRIB|INITATMOS|LBCS|MODEL|POST) ;;
        *)
            echo "ERROR: Unknown resource stage: $stage" >&2
            return 1
            ;;
    esac

    for suffix in NODES MPI_PER_NODE REQUESTED_WALLTIME QUEUE_MODE; do
        name="${stage}_${suffix}"
        if [[ -z "${!name:-}" ]]; then
            echo "ERROR: Set $name in run_config.local.bash." >&2
            return 1
        fi

        # Preserve requested settings in child scripts and PBS jobs.
        export "$name"
    done

    name="${stage}_NODES";              nodes="${!name}"
    name="${stage}_MPI_PER_NODE";       ranks="${!name}"
    name="${stage}_REQUESTED_WALLTIME"; walltime="${!name}"
    name="${stage}_QUEUE_MODE";         mode="${!name}"
    name="${stage}_MANUAL_QUEUE";       manual="${!name:-}"

    if [[ ! "$nodes" =~ ^[1-9][0-9]*$ ||
          ! "$ranks" =~ ^[1-9][0-9]*$ ]]; then
        echo "ERROR: ${stage}_NODES and ${stage}_MPI_PER_NODE must be positive integers." >&2
        return 1
    fi

    if [[ "$walltime" =~ ^([0-9]{1,3}):([0-5][0-9]):([0-5][0-9])$ ]]; then
        seconds=$((10#${BASH_REMATCH[1]} * 3600 +
                   10#${BASH_REMATCH[2]} * 60 +
                   10#${BASH_REMATCH[3]}))
    else
        echo "ERROR: ${stage}_REQUESTED_WALLTIME must use HH:MM:SS or HHH:MM:SS." >&2
        return 1
    fi

    if (( seconds <= 0 )); then
        echo "ERROR: ${stage}_REQUESTED_WALLTIME must be positive." >&2
        return 1
    fi

    total=$((nodes * ranks))

    case "$mode" in
        auto)
            # First compatible queue in this preference order.
            # CPUs=0: no queue-level CPU limit in the supplied qstat.
            # Physical node capacity and server/user limits still apply.
            while read -r queue max_seconds max_nodes max_cpus; do
                if (( seconds <= max_seconds &&
                      nodes <= max_nodes &&
                      (max_cpus == 0 || total <= max_cpus) )); then
                    selected="$queue"
                    break
                fi
            done <<'QUEUES'
pesqmini 1800    7 1792
pesqmidi 7200    7 0
pesqhigh 21600  20 0
pesqextra 28800 30 0
longtime 604800  8 0
QUEUES

            if [[ -z "$selected" ]]; then
                echo "ERROR: No configured research queue fits $stage." >&2
                echo "  Nodes=$nodes CPUs=$total walltime=$walltime" >&2
                return 1
            fi
            ;;
        manual)
            if [[ ! "$manual" =~ ^[[:alnum:]_][[:alnum:]_.-]*$ ]]; then
                echo "ERROR: Set a valid ${stage}_MANUAL_QUEUE." >&2
                return 1
            fi
            name="${stage}_MANUAL_QUEUE"
            export "$name"
            selected="$manual"
            # PBS validates the queue's limits and access permissions.
            ;;
        *)
            echo "ERROR: ${stage}_QUEUE_MODE must be auto or manual." >&2
            return 1
            ;;
    esac

    # Existing variable names consumed by the submission scripts.
    export "${stage}_nnodes=$nodes"
    export "${stage}_ncpn=$ranks"
    export "${stage}_ncpus=$ranks"
    export "${stage}_nthreads=1"
    export "${stage}_ncores=$total"
    export "${stage}_walltime=$walltime"
    export "${stage}_QUEUE=$selected"

    if [[ "$quiet" != "quiet" ]]; then
        printf '%s: queue=%s (%s), nodes=%s, MPI/node=%s, total MPI=%s, walltime=%s\n' \
            "$stage" "$selected" "$mode" "$nodes" "$ranks" "$total" "$walltime"
    fi

    return 0
}

configure_workflow_resources() {
    local stage
    for stage in ${MONAN_RESOURCE_STAGES:-}; do
        configure_stage_resources "$stage" "${1:-}" || return 1
    done
}
