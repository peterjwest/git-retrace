#! /usr/bin/env bash

# TODO:
# - Support submodules or subtree

set -euo pipefail

command=${1:-}
commandName=$(basename "$0")
usage="$(cat <<EOF

Usage: $commandName [--continue | --abort] [-h | --help]

Split a commit into multiple commits by working backwards.
Undo some of the changes and run \`$commandName --continue\` to commit them.
Repeat until you have no changes left, then run \`$commandName --continue\` to finish the process.

Run \`$commandName --abort\` to abort the process at any time.

Options
  --continue  Split the commit further
  --abort     Abort the process and return to the original commit
  --status    Reports the status of retrace
  -h, --help  Print this usage information
EOF
)"

statusAdvice="$(cat <<EOF

Unstage some of your changes and commit them with:

  $commandName --continue

The process will automatically finish when \`$commandName --continue\` is run with no changes staged.

Abort the process at any time with:

  $commandName --abort
EOF
)"

for var in "$@"; do
  case "$var" in
    -h|--help)
      echo "$usage"
      echo ""

      exit 0
    ;;
  esac
done

if ! git rev-parse --show-toplevel; then
  echo "Error: Not in a Git repository"
  exit 1
fi

gitRoot=$(git rev-parse --show-toplevel)

if [[ -d ${gitRoot}/.git ]]; then
  gitDir=${gitRoot}/.git
else
  gitDir=$(cat ${gitRoot}/.git | sed 's/gitdir: //')
fi

# Iterate through options and respond accordingly
for var in "$@"; do
  case "$var" in
    --status)
      if [ ! -d "$gitDir/retrace" ]; then
        echo "Git retrace not in progress"
      else
        branch="$(cat $gitDir/retrace/BRANCH)"
        echo "Git retrace in progress on branch $branch ($(git rev-parse --short $branch))"
        echo "$statusAdvice"
        echo ""
      fi

      exit 0
    ;;
    --continue)
      if [ ! -d "$gitDir/retrace" ]; then
        echo "Git retrace not in progress"
        exit 1
      fi

      branch="$(cat $gitDir/retrace/BRANCH)"
      baseCommit="$(git rev-parse "$branch^")"
      currentCommit="$(git rev-parse HEAD)"

      if [[ "$baseCommit" != "$currentCommit" ]]; then
        echo ""
        echo "Unexpected commit, don't commit during retrace!"
        echo "Aborting"

        git clean -f
        git reset --hard

        git checkout .
        git checkout "$branch" -q
        git branch -D git/retrace
        rm -rf $gitDir/retrace

        exit 1
      fi

      git clean -f
      git restore .

      # Create a temp commit
      git commit --allow-empty -m "Retrace temp"
      tempCommit="$(git rev-parse HEAD)"

      # Take the temp commit and apply it reverted to the temporary branch
      git checkout git/retrace -q
      git diff git/retrace "$tempCommit" --binary | git apply --index
      count="$(cat $gitDir/retrace/COUNT)"
      git commit --allow-empty -m "Retrace N-$((count++))"
      echo $count > $gitDir/retrace/COUNT

      # Checkout the base commit again
      git checkout "$baseCommit" -q

      # Apply remaining changes by cherry picking the original large commit,
      # and all subsequent removals as one diff
      git cherry-pick "..git/retrace" -n

      # If the diff is empty, finish
      if [ -z "$(git status --porcelain)" ]; then

        git rev-list "$branch..git/retrace"

        count=1

        # Apply the reverse of all the commits replacing the original commit
        for tempCommit in $(git rev-list "$branch..git/retrace"); do
          git revert "$tempCommit" --no-commit
          git commit -m "Retrace $((count++))"
        done
        final="$(git rev-parse HEAD)"

        git branch -f "$branch" "$final"
        git checkout "$branch"

        git branch -D git/retrace

        if [[ $(git config --get rebase.autoStash) == 'true' && $(cat $gitDir/retrace/STASH) == 'true' ]]; then \
          git stash pop
        fi

        rm -rf $gitDir/retrace

        exit 0
      fi

      exit 0
    ;;
    --abort)
      echo "Aborting"

      if [ ! -d "$gitDir/retrace" ]; then
        echo "Git retrace not in progress"
        exit 1
      fi

      git clean -f
      git reset --hard

      branch="$(cat $gitDir/retrace/BRANCH)"
      git checkout .
      git checkout "$branch" -q
      git branch -D git/retrace
      rm -rf $gitDir/retrace

      exit 0
    ;;
    -*|--*)
      echo "Unknown option: '$1'"
      echo "$usage"
      echo ""

      exit 1
    ;;
  esac
done

if [ -d "$gitDir/retrace" ]; then
  branch="$(cat $gitDir/retrace/BRANCH)"
  echo "Git retrace already in progress on $branch ($(git rev-parse --short $branch))"
  echo "$statusAdvice"
  echo ""

  exit 1
fi

branch="$(git symbolic-ref --short HEAD -q)"

if [[ ! $branch ]]; then
  echo "Error: Git retrace only works on a branch, you are in detatched HEAD state"
  exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  if [[ $(git config --get rebase.autoStash) != 'true' ]]; then
    echo 'Error: uncommitted changes, Git retrace requires a clean branch, or enable rebase.autoStash.'
    exit 1
  fi
fi

echo "Starting git retrace on $(git symbolic-ref --short HEAD -q) ($(git rev-parse --short HEAD))"

mkdir -p $gitDir/retrace

echo "$branch" > $gitDir/retrace/BRANCH
echo "1" > $gitDir/retrace/COUNT

if ! git diff --quiet || ! git diff --cached --quiet; then
  message="Autostash. Git retrace '$branch' $(date '+%d %b %Y at %H:%M')"
  git stash push --quiet --include-untracked --message "$message"
  echo "true" > $gitDir/retrace/STASH
else
  echo "false" > $gitDir/retrace/STASH
fi

git branch git/retrace $(git rev-parse HEAD)

baseCommit="$(git rev-parse "$branch^")"
git checkout "$baseCommit" -q
git cherry-pick "..$branch" -n
