#!/bin/sh
##
# Unlock.sh
# Clear the OS9 lock flag on a file.
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
done
