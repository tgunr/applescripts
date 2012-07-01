#!/bin/sh
##
# Nuke.sh
# Delete a file, even if the OS9 lock flag is on.
#
# Wordman | http://www.divnull.com/lward/
# using the ultra-cool DropScript from 
# Wilfredo Sanchez | wsanchez@opensource.apple.com
##

# EXTENSIONS : "*"
# OSTYPES    : "****"

for file; do
  location=$(dirname "$file")
  cd "${location}"
  chflags -R nouchg "${file}"
  rm -Rf "${file}"
done
