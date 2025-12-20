#!/bin/bash

# Loop through each file in each directory
for file in "db"/*schema "script"/* "public"/* "templates"/* "lib"/* ; do
    # Check if it is a file
    if [[ -f "$file" ]]; then
        # Echo the filename
        echo "#Filename: $(basename "$file")"
        
        # Display the content of the file
        cat "$file"
        echo
    fi
done


