#!/bin/bash

cat $0
exit

# -------- sorry, not implemented yet
#
# for now, just read this and be happy!

# FIRST: DO NOT USE THE BUILTIN 'git cvsimport'.  Problems I had using it
# include missing tags, branches grafted to the wrong place (by comparing a
# --simplify-by-decoration tree later), missing commits (which is what
# originally made me start investigating), and even missing files in the root
# of the repo, like Makefile!!

# part 1

# - download cvs2svn version 2.1 or higher from somewhere within
#   http://cvs2svn.tigris.org/cvs2git.html
#   DO NOT BE DISTRACTED BY THE MISLEADING REFERENCES TO A MYTHICAL "cvs2git"
#   COMMAND IN THAT PAGE :)

# - expand it somewhere, and cd there

# - in there, create an options file from the original, like shown in the diff
#   at the end of this file (change accordingly of course; this diff only
#   shows where you should make the changes, not what)
#   (Avoid using the "test-data/main-cvsrepos/cvs2svn-git-inline.options" file
#   as a starting point.  I thought that would be a single step process, but
#   it still needed 2 steps, and the intermediate files were 3X larger.
#   However, the output seems to be closer to the original CVS in terms of the
#   $Id stuff.  YMMV)

# - run
#       ./cvs2svn --options=my.c2soptions
# - when it completes, check the 'cvs2svn-tmp' directory for 2 files

# part 2

# - make an empty directory, cd to it, git init, then run
#       cat ~-/cvs2svn-tmp/git-{blob,dump}.dat | git fast-import

# that should do...
cat <<EOF >/dev/null
diff --git 1/test-data/main-cvsrepos/cvs2svn-git.options 2/my.c2soptions
index 46510eb..fb26b6f 100644
--- 1/test-data/main-cvsrepos/cvs2svn-git.options
+++ 2/my.c2soptions
@@ -41,7 +41,7 @@ ctx.cross_branch_commits = False
 # record the original author (for example, the creation of a branch).
 # This should be a simple (unix-style) username, but it can be
 # translated into a git-style name by the author_transforms map.
-ctx.username = 'cvs2svn'
+ctx.username = 'someone'
 
 # CVS uses unix login names as author names whereas git requires
 # author names to be of the form "foo <bar>".  The default is to set
@@ -61,7 +61,7 @@ author_transforms={
 
     # This one will be used for commits for which CVS doesn't record
     # the original author, as explained above.
-    'cvs2svn' : ('cvs2svn', 'admin@example.com'),
+    'someone' : ('someone', 'someone@your.company.com'),
     }
 
 # This is the main option that causes cvs2svn to output to git rather
@@ -119,7 +119,7 @@ run_options.add_project(
     # The path to the part of the CVS repository (*not* a CVS working
     # copy) that should be converted.  This may be a subdirectory
     # (i.e., a module) within a larger CVS repository.
-    r'test-data/main-cvsrepos',
+    r'path/to/cvsroot/module',
 
     # See cvs2svn-example.options for more documention about symbol
     # transforms that can be set using this option.
EOF
