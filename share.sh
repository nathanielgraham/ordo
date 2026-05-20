#!/bin/bash

# Loop through each file in each directory
#for file in "db"/*schema "script"/* "public"/* "templates"/* "lib"/* ; do
#for file in "lib"/*pm "lib/ordo/Model"/* "lib/ordo/Controller"/* "templates"/* ; do
#for file in "templates"/*app.html.ep "templates/partials"/*ep "public/css"/app.css "public/js"/*js "public/js/tree"/*js; do
#for file in "templates"/*app.html.ep "templates/partials"/*ep "public/js"/*js "public/js/tree"/*js; do
for file in "public/docs/"*md; do
    # Check if it is a file
    if [[ -f "$file" ]]; then
        # Echo the filename
        echo "#Filename: $(basename "$file")"
        
        # Display the content of the file
        cat "$file"
        echo
    fi
done
