#!/bin/bash
# This script creates a new branch in the current git repository.
# Usage: ./create-branch.sh <branch-name>
# Example: ./create-branch.sh feature/new-feature
# Check if the branch name is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <branch-name>"
  exit 1
fi
# Check if the .git directory exists
if [ ! -d ".git" ]; then
  echo "Error: .git directory not found. Make sure you are in a git repository."
  exit 1
fi
# Check if the .git/HEAD file is writable
if [ ! -w ".git/HEAD" ]; then
  echo "Error: .git/HEAD file is not writable. Check your permissions."
  exit 1
fi
# Check if the branch name is valid
if [[ ! "$1" =~ ^[a-zA-Z0-9/_-]+$ ]]; then
  echo "Error: Invalid branch name. Only alphanumeric characters, underscores, and dashes are allowed."
  exit 1
fi
# Check if the branch name is too long
if [ ${#1} -gt 255 ]; then
  echo "Error: Branch name is too long. Maximum length is 255 characters."
  exit 1
fi
# Check if the .git/HEAD file exists
if [ ! -f ".git/HEAD" ]; then
  echo "Error: .git/HEAD file not found. Make sure you are in a git repository."
  exit 1
fi
# Check if the branch already exists
if git show-ref --verify --quiet "refs/heads/$1"; then
  echo "Error: Branch '$1' already exists."
  exit 1
fi
# Create the new branch
git branch "$1"
# Check if the command was successful
if [ $? -eq 0 ]; then
  echo "Successfully created branch '$1'."
else
  echo "Error: Failed to create branch '$1'."
  exit 1
fi
# Check if the branch name is valid
if git show-ref --verify --quiet "refs/heads/$1"; then
  echo "Branch '$1' exists."
else
  echo "Warning: Branch '$1' does not exist. You may want to create it."
fi