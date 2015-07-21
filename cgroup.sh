#!/bin/bash

# Copyright 2015, SolidFire, Inc. All rights reserved.

source "${BASHUTILS}/efuncs.sh"   || { echo "Failed to find efuncs.sh" ; exit 1; }

#-------------------------------------------------------------------------------
# Cgroups are a capability of the linux kernel designed for categorizing
# processes.  They're most typically used in ways that not only categorize
# processes, but also control them in some fasion.  A popular reason is to
# limit the amount of resources a particular process can use.
#
# Within each of many different _subsystems_ that are set up by code in the
# kernel, a process may exist at one point in a hierarchy.  That is, within the
# CPU subsystem, a process may only be owned by a single cgroup.  And in the
# memory subsystem, it may be owned by a different cgroup.  For the purposes of
# THIS bashutils code, though, we duplicate a similar tree of groups within
# _all_ of the subsystems that we interact with.
#
# CGROUPS_SUBSYSTEMS defines which subsystems those are. So when you use these
# functions, the hierarchy that you create is created in parallel under all of
# the subsystems defined by CGROUPS_SUBSYSTEMS.
#
# Positions within the cgroup hierarchy created here are identified by names
# that look like relative directories.  This is no accident -- cgroups are
# represented to the kernel by a directory structure created within a
# filesystem of type cgroups.
#
# Hopefully these functions make accessing the cgroups filesystem a little bit
# easier, and also help you to keep parallel hierarchies identical across the
# various cgroups subsystems.
#
#-------------------------------------------------------------------------------

CGROUPS_SUBSYSTEMS=(cpu memory freezer)

#-------------------------------------------------------------------------------
# Add one or more processes to a specific cgroup.  Once added, all children of
# that process will also automatically go into that cgroup.
#
# $1:   The name of a cgroup (e.g. distbox/distcc or colorado/denver or alpha)
# rest: PIDs of processes to add to that cgroup (NOTE: empty strings are
#       allowed, but have no effect on cgroups)
#
# Example:
#      cgroup_add distbox $$
#
cgroup_add()
{
    $(declare_args cgroup)
    cgroup_create ${cgroup}

    local pids=( "${@}" )

    array_remove -a pids ""

    if [[ $(array_size pids) -gt 0 ]] ; then
        einfo X"$(array_join_nl pids)"X
        for subsystem in ${CGROUPS_SUBSYSTEMS[@]} ; do
            # NOTE: Use /bin/echo instead of bash echo because /bin/echo checks
            # write errors, while bash's does not.  (per FAQ at
            # https://www.kernel.org/doc/Documentation/cgroups/cgroups.txt)
            echo "$(array_join_nl pids)" > /sys/fs/cgroup/${subsystem}/${cgroup}/tasks
        done
    fi
}

#-------------------------------------------------------------------------------
# Change the value of a cgroups subsystem setting for the specified cgroup.
# For instance, by using the memory subsystem, you could limit the amount of
# memory used by all pids underneath the distbox hierarchy like this:
#
#     cgroup_set distbox memory.kmem.limit_in.bytes $((4*1024*1024*1024))
#
#  $1: Name of the cgroup (e.g. distbox/distcc or fruit/apple or fruit)
#  $2: Name of the subsystem-specific setting
#  $3: Value that should be assigned to that subsystem-specific setting
#
cgroup_set()
{
    $(declare_args cgroup setting value)
    cgroup_create ${cgroup}

    /bin/echo "${value}" > $(cgroup_find_setting_file ${cgroup} ${setting})
}

#-------------------------------------------------------------------------------
# Read the existing value of a subsystem-specific cgroups setting for the
# specified cgroup.  See cgroup_set for more info
#
# $1: Name of the cgroup (i.e. distbox/dtest or usa/colorado)
# $2: Name of the subsystem-specific setting (e.g. memory.kmem.limit_in.bytes)
#
cgroup_get()
{
    $(declare_args cgroup setting)
    cat $(cgroup_find_setting_file ${cgroup} ${setting})
}

#-------------------------------------------------------------------------------
# Recursively find all of the pids that live underneath a specified portion of
# the cgorups hierarchy.
#
# $1: Name of the cgroup (e.g. flintstones/barney or distbox/sshd)
#
cgroup_pids()
{
    $(declare_args cgroup)

    # NOTE: The pids should be identical in all of the different cgroup
    # subsystems, so we arbitrarily choose one and look at it
    cat $(find /sys/fs/cgroup/${CGROUPS_SUBSYSTEMS[0]}/${cgroup} -name tasks)
}

#-------------------------------------------------------------------------------
# Recursively KILL (or send a signal to) all of the pids that live underneath a
# specified portion of the cgorups hierarchy.
#
# $1: Name of the cgroup (e.g. flintstones/barney or distbox/sshd)
#
# Options:
#       -s=<signal>
#
cgroup_kill()
{
    $(declare_args cgroup)
    edebug "Killing pids in cgroup $(lval cgroup)"
    local signal=$(opt_get s SIGTERM)

    ekill -${signal} $(cgroup_pids ${cgroup})
}

cgroup_find_setting_file()
{
    $(declare_args cgroup setting)
    ls /sys/fs/cgroup/*/${cgroup}/${setting}
}

# This function is mostly internal.  Other cgroups functions use it to create
# the cgroup hierarchy on demand.
cgroup_create()
{
    for cgroup in "${@}" ; do

        for subsystem in ${CGROUPS_SUBSYSTEMS[@]} ; do
            local subsys_path=/sys/fs/cgroup/${subsystem}/${cgroup}
            mkdir -p ${subsys_path}

            #echo 1 > ${subsys_path}/notify_on_release
        done

    done
}

