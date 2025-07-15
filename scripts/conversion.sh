#!/usr/bin/env bash

# Set quality level
QUALITY=100

# Find all PNG files excluding 'themes/' directory and convert them to WebP
find . -type f -iname "*.png" ! -path "*/themes/*" ! -path "*/public/*" ! -path "*/_gen/*" | while read -r file; do
    output="${file%.*}.webp"
    echo "Converting $file -> $output"
    cwebp -q $QUALITY "$file" -o "$output"
    rm "${file}"
done

echo "Conversion complete."
