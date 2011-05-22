#!/bin/bash

# -----------------------------------------------------------------------------
# Usage
# -----------------------------------------------------------------------------
#   This file should be sourced into your bashrc.

# -----------------------------------------------------------------------------
# in brief:
# -----------------------------------------------------------------------------
#     shows a color-coded count of files in various states: unmerged (bold
#     red), untracked (blue), modified (red), and staged (green).  In
#     addition, the branch name reported by __git_ps1 is also colored
#     (for example, bright red when the head is detached).

# -----------------------------------------------------------------------------
# Color customisation
# -----------------------------------------------------------------------------
# CAPS indicate color+bold.  Color stuff lifted from
# git://github.com/lvv/git-prompt.git, with some minor changes (added
# 'unmerged', for instance)
         init_vcs_color=magenta   # initial
        clean_vcs_color=blue      # nothing to commit (working directory clean)
     modified_vcs_color=red       # Changed but not updated:
        added_vcs_color=green     # Changes to be committed:
        mixed_vcs_color=yellow    #
    untracked_vcs_color=BLUE      # Untracked files:
     detached_vcs_color=RED
     unmerged_vcs_color=MAGENTA

# =============================================================================

# source the git-supplied completion file
. ~/git-completion.bash

# -----------------------------------------------------------------------------
# this function sets __git_ps1_text when called.

__git_ps1_plus()
{
    git_dir=`git rev-parse --git-dir 2> /dev/null`
    [[ -n "$git_dir" ]] || {
        # not in a git dir?  reset display field; return
        __git_ps1_text=
        return
    }

    local gitps1; gitps1=$(__git_ps1)

    # this is the notionally expensive stuff -- run 'git status', parse it,
    # and convert the whole thing to colors and numbers

    # mostly lifted from git://github.com/lvv/git-prompt.git, with the
    # following broad changes
    # - remove stuff that __git_ps1 already does
    # - remove display of file *names*; just display file counts instead
    local status modified added clean init mixed untracked detached unmerged
    local added_files modified_files unmerged_files untracked_files
    eval `
            git status 2>/dev/null |
                sed -n '
                    s/^nothing to commit (working directory clean)/clean=clean/p
                    s/^# Initial commit/init=init/p
                    /^# Untracked files:/,/^[^#]/{
                        s/^# Untracked files:/untracked=untracked;/p
                        s/^#	\([^ ].*\)/(( untracked_files += 1 ));/p
                    }
                    /^# Unmerged paths:/,/^# [A-Z]/ {
                        s/^# Unmerged paths:/unmerged=unmerged;/p
                        s/^#	unmerged: *\([^ ].*\)/(( unmerged_files += 1 ));/p
                        s/^#	both modified: *\([^ ].*\)/(( unmerged_files += 1 ));/p
                    }
                    /^# Changes not staged for commit:/,/^# [A-Z]/ {
                        s/^# Changed but not updated:/modified=modified;/p
                        s/^#	unmerged: *\([^ ].*\)/(( unmerged_files += 1 ));/p
                        s/^#	modified: *\([^ ].*\)/(( modified_files += 1 ));/p
                        s/^#	deleted: *\([^ ].*\)/(( modified_files += 1 ));/p
                    }
                    /^# Changes to be committed:/,/^# [A-Z]/ {
                        s/^# Changes to be committed:/added=added;/p
                        s/^#	modified: *\([^ ].*\)/(( added_files += 1 ));/p
                        s/^#	new file: *\([^ ].*\)/(( added_files += 1 ));/p
                        s/^#	renamed:[^>]*> \([^ ].*\)/(( added_files += 1 ));/p
                        s/^#	copied:[^>]*> \([^ ].*\)/(( added_files += 1 ));/p
                    }
                '
    `

    grep -q "^ref:" $git_dir/HEAD  2>/dev/null
    if  ! grep -q "^ref:" $git_dir/HEAD  2>/dev/null;   then
        detached=detached
    fi

    unset status
    [[ $modified && $added ]] && mixed=mixed
    [[ $unmerged_files ]] && unmerged=unmerged
    status=${status:-$detached}
    status=${status:-$clean}
    status=${status:-$unmerged}
    status=${status:-$mixed}
    status=${status:-$modified}
    status=${status:-$added}
    status=${status:-$untracked}
    status=${status:-$init}
        # at least one should be set
        : ${status?prompt internal error: git status}
    eval vcs_color="\${${status}_vcs_color}"

    ### file list
    unset file_list
    [[ $added_files     ]]  &&  file_list+=" "$added_vcs_color$added_files
    [[ $modified_files  ]]  &&  file_list+=" "$modified_vcs_color$modified_files
    [[ $unmerged_files  ]]  &&  file_list+=" "$unmerged_vcs_color$unmerged_files
    [[ $untracked_files ]]  &&  file_list+=" "$untracked_vcs_color$untracked_files
    # file_list=${file_list:+:$file_list}

    # for i in status modified added clean init added mixed untracked detached file_list
    # do
        # echo $i=${!i}
    # done
    __git_ps1_text=$vcs_color$gitps1$file_list
}

# -----------------------------------------------------------------------------
# The following code was originally with the color choice code above, but I
# separated them to put the customisable stuff at the top and the rest here,
# where it's out of the way
# -----------------------------------------------------------------------------

# color stuff lifted from git://github.com/lvv/git-prompt.git, with some minor
# changes (added 'unmerged', for instance)

      black=`tput sgr0; tput setaf 0`
        red=`tput sgr0; tput setaf 1`
      green=`tput sgr0; tput setaf 2`
     yellow=`tput sgr0; tput setaf 3`
       blue=`tput sgr0; tput setaf 4`
    magenta=`tput sgr0; tput setaf 5`
       cyan=`tput sgr0; tput setaf 6`
      white=`tput sgr0; tput setaf 7`

      BLACK=`tput setaf 0; tput bold`
        RED=`tput setaf 1; tput bold`
      GREEN=`tput setaf 2; tput bold`
     YELLOW=`tput setaf 3; tput bold`
       BLUE=`tput setaf 4; tput bold`
    MAGENTA=`tput setaf 5; tput bold`
       CYAN=`tput setaf 6; tput bold`
      WHITE=`tput setaf 7; tput bold`

    bw_bold=`tput bold`
       bell=`tput bel`

colors_reset=`tput sgr0`

# replace symbolic colors names to raw treminfo strings
         init_vcs_color=${!init_vcs_color}
     modified_vcs_color=${!modified_vcs_color}
    untracked_vcs_color=${!untracked_vcs_color}
        clean_vcs_color=${!clean_vcs_color}
        added_vcs_color=${!added_vcs_color}
        mixed_vcs_color=${!mixed_vcs_color}
     detached_vcs_color=${!detached_vcs_color}
     unmerged_vcs_color=${!unmerged_vcs_color}
