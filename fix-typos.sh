#!/bin/bash

echo "Fixing 'successfull' typos in codebase..."

# Fix TypeScript/JavaScript files
find /mnt/c/Users/jehma/Desktop/DGMSTT -type f \( -name "*.ts" -o -name "*.js" \) -exec sed -i 's/successfull/successful/g' {} \;

# Fix Python files  
find /mnt/c/Users/jehma/Desktop/DGMSTT -type f -name "*.py" -exec sed -i 's/successfull/successful/g' {} \;

# Fix Go files
find /mnt/c/Users/jehma/Desktop/DGMSTT -type f -name "*.go" -exec sed -i 's/successfull/successful/g' {} \;

# Fix Markdown files
find /mnt/c/Users/jehma/Desktop/DGMSTT -type f -name "*.md" -exec sed -i 's/successfull/successful/g' {} \;

# Fix shell scripts
find /mnt/c/Users/jehma/Desktop/DGMSTT -type f -name "*.sh" -exec sed -i 's/successfull/successful/g' {} \;

echo "Typo fixes complete!"