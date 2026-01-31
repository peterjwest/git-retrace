# Git retrace

## Split a commit into multiple commits by working backwards

Git retrace exists to simplify rebasing large commits.
It works by letting you work backwards from the finished commit, splitting as you go.

## Rationale

This repository has a branch `example-repo` which you can use to test this utility.

Clone this repository then run `git submodule init`, `git submodule update` to download this branch into the `example-repo` folder.

This branch has a commit "Example large commit" which we want to split. The commit creates/updates 6 files, which depend on each other (with pseudo-code `import` statements):

```
      A
     /  \
    B    \
   / \    |
  |   C   |
   \ / \ /
    D   F
    |
    E
```

How can we split this commit? Well you _could_ remove the import and any related code from A, stage it and stash the other files, then commit A, unstash the files and then redo the changes to A. Then repeat this process for every further commit you want to split.

This requires removing a lot of files from each commit and adding them back again; which tends to be very error prone.

Git retrace approaches this from the other direction, by removing features one by one, the process is much simpler.

## Usage

1) Check out the commit you want to rebase
2) Start Git Retrace: `git retrace`, this works similarly to a rebase (your repo will be in a detatched head state until the retrace is finished). This will give you the whole commit as a staged diff
3) Undo some portion of the changes (anything unstaged will also be removed)
4) Run `git retrace --continue`, the remaining diff of the original commit will be staged
5) Repeat steps 3 and 4, until you're happy with the size of the remaining diff
6) Run `git retrace --continue` with the remaining diff staged to finish the process

If anything goes wrong you can run `git retrace --abort` to revert all changes.

## Installation

You can use this as a standalone bash script e.g. `./retrace.sh`, or install it as a git alias:

```bash
git config --global alias.retrace '!/path/to/retrace.sh'
```
