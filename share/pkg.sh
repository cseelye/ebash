#!/usr/bin/env bash
#
# Copyright 2016 SolidFire, Inc. All rights reserved.
#

opt_usage pkg_exists <<'END'
Determine if the package management system locally knows of a package with the specified name.  This
won't update the package database to do its check.
END
pkg_exists()
{
    $(opt_parse \
        "name | Name of package to look for.")

    case $(pkg_manager) in
        dpkg)
            apt-cache show ${name} &>/dev/null
            ;;

        portage)

            name=$(pkg_gentoo_find_with_category ${name})
            [[ -d /usr/portage/${name} ]]
            ;;

        dnf)
            dnf list ${name} &>/dev/null
            ;;

        pacman)
            pacman -Ss ${name} &>/dev/null
            ;;

        *)
            die "Unsupported package manager $(pkg_manager)"
            ;;
    esac
}

pkg_gentoo_find_with_category()
{
    $(opt_parse "name | Package name whose category you'd like to find.")

    if [[ ${name} == */* ]] ; then
        echo "${name}"

    else

        local found=( "/usr/portage/*/${name}" )
        local size=$(array_size found)

        if [[ ${size} -eq 0 ]] ; then
            return 1

        elif [[ ${size} -eq 1 ]] ; then
            echo "${found[0]}"

        else
            die "${name} is ambiguous.  You must specify a category."
        fi
    fi
}

pkg_installed()
{
    $(opt_parse \
        "name | Name of package to look for.")

    case $(pkg_manager) in
        dpkg)
            local pkg_status="$(dpkg -s "${name}" 2>/dev/null | grep '^Status:')"
            [[ "${pkg_status}" == 'Status: install ok installed' ]]
            ;;

        portage)

            name=$(pkg_gentoo_find_with_category ${name})
            [[ -d /var/db/pkg/${name} ]]
            ;;

        dnf)
            dnf list installed ${name} &>/dev/null
            ;;

        pacman)
            pacman -Q ${name} &>/dev/null
            ;;

        *)
            die "Unsupported package manager $(pkg_manager)"
            ;;
    esac

}

opt_usage pkg_install <<'END'
Install some set of packages whose names are specified.  Note that while this function supports
several different package managers, packages may have different names on different systems.
END
pkg_install()
{
    $(opt_parse "@names | Names of package to install.")

    local pkg_manager=$(pkg_manager)

    case ${pkg_manager} in
        dpkg)
            pkg_install_dpkg "${@}"
            ;;

        portage)
            if ! pkg_exists "${@}" ; then
                eix-sync
            fi

            emerge --ask=n "${@}"
            ;;


        dnf)
            dnf install -y "${@}"
            ;;


        pacman)
            if ! pkg_exists "${@}" ; then
                pacman -Sy
            fi

            pacman -S --noconfirm "${@}"
            ;;

        *)
            die "Unsupported package manager $(pkg_manager)"
            ;;
    esac

    einfo BYE
}

pkg_install_dpkg()
{
    (
        set +e

        export DEBIAN_FRONTEND=noninteractive

        # Try the install in basic form first off.  If it passes, we don't need to update sources or do
        # anything else.  OTOH, if it fails, we have ways of making apt do what it's told.
        apt-get -y install "${@}"
        if [[ $? == 0 ]] ; then
            return 0
        fi

        # This command cleans up some caches that like to cause apt to cough up a
        # segfault.
        local F_APT="find /var/lib/apt/lists -type f -a ! -name lock -a ! -name partial -delete"

        # Most of these commands simply try to clean up bad situations that apt
        # likes to get itself in.  Each item in this list will be run until it
        # succeeds or we run out of retries.
        #
        #
        local commands_left=(
            "dpkg --force-confdef --force-confold --configure -a"
            "${F_APT} ; apt-get -f -y --force-yes install"
            # Note: ignore failures from apt-get update here.  Sometimes it fails because of a repo
            # we don't care about.  All we care is that we can install our own packages.
            "${F_APT} ; apt-get update ; apt-get -y install \${@}"
            )


        # Loop until we run out of chances, or until all of these commands have run successfully
        local attempts=0
        while [[ ${#commands_left[@]} -gt 0 ]] ; do

            # Iterate over the commands that have not passed yet
            local cmd cmd_rc
            for cmd in "${commands_left[@]}" ; do

                # Run this one
                eval ${cmd}
                cmd_rc=$?

                edebug "Ran ${cmd} with exit ${cmd_rc}"

                # If it was successful, remove it from the list
                if [[ ${cmd_rc} -eq 0 ]] ; then
                    commands_left=("${commands_left[@]:1}")
                else
                    # If not, wait for the next retry
                    break;
                fi

            done


            # If any of the commands failed, prepare to retry
            if [[ ${#commands_left[@]} -ne 0 ]] ; then

                # Sleep a random amount between 3 and 7 seconds
                local random=$(( $RANDOM % 5 + 3))
                edebug "Waiting ${random} seconds before trying to install ${@} again."
                sleep ${random}

                # Prepare for the next attempt unless we've already waited too long
                (( attempts++ ))
                [[ ${attempts} -gt 60 ]] && break
                [[ $(( attempts % 3 )) -eq 0 ]] && einfo "Unable to install ${@} after ${attempts} tries.  Still trying..."
            fi
        done

        set -e

        exit ${apt_rc}
    )
}

pkg_uninstall()
{
    $(opt_parse "@names | Names of package to install.")

    case $(pkg_manager) in
        dpkg)
            aptitude purge -y "${@}"
            ;;

        portage)
            emerge --ask=n --unmerge "${@}"
            ;;


        dnf)
            dnf remove -y "${@}"
            ;;


        pacman)
            pacman -R --noconfirm "${@}"
            ;;

        *)
            die "Unsupported package manager $(pkg_manager)"
            ;;
    esac
}

pkg_database_update()
{
    case $(pkg_manager) in
        dpkg)
            apt-get update
            ;;

        portage)
            eix-sync
            ;;

        dnf)
            # dnf doesn't give you the option to do this separately -- it may do it as often as
            # every call, depending on system configuration
            :
            ;;

        pacman)
            pacman -Sy
            ;;

        default)
            die "Unsupported package manager $(pkg_manager)"
            ;;
    esac
}


pkg_manager()
{
    if os_distro ubuntu mint debian ; then
        echo "dpkg"

    elif os_distro fedora; then
        echo "dnf"

    elif os_distro gentoo ; then
        echo "portage"

    elif os_distro arch ; then
        echo "pacman"

    else
        echo "unknown"
        return 1
    fi
}